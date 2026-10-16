#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import os
import pathlib
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest


class BuildSupportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="build support ")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shutil.copyfile(pathlib.Path(__file__).parents[1] / "build_support.py",
                        self.root / "build_support.py")
        self.runner = self.root / "runner.py"
        self.runner.write_text(textwrap.dedent('''\
            import os, sys
            from build_support import run_build, run_cli, run_command
            def main():
                if sys.argv[1] == "command":
                    return run_command(sys.argv[2:])
                return run_build(sys.argv[2:], log_path=os.environ.get("TEST_RAW_LOG"))
            run_cli(main)
        '''))
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin",
                    "PYTHONDONTWRITEBYTECODE": "1"}
        self.env.pop("GITHUB_ACTIONS", None)
        self.env.pop("TEST_RAW_LOG", None)

    def formatter(self):
        formatter = self.bin / "xcbeautify"
        formatter.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''\
            import json, os, pathlib, shutil, sys
            if os.environ.get("FORMAT_ARGS"):
                pathlib.Path(os.environ["FORMAT_ARGS"]).write_text(json.dumps(sys.argv[1:]))
            shutil.copyfileobj(sys.stdin.buffer, sys.stdout.buffer)
            sys.exit(int(os.environ.get("FORMAT_EXIT", "0")))
        '''))
        formatter.chmod(0o755)

    def command(self, source, mode="build"):
        return [sys.executable, str(self.runner), mode, sys.executable, "-c", source]

    def run_source(self, source, mode="build"):
        return subprocess.run(self.command(source, mode), env=self.env,
                              capture_output=True, timeout=15)

    def test_live_output_is_merged_without_formatter(self):
        release = self.root / "release"
        source = ("import pathlib, sys, time; print('ready', flush=True); "
                  f"release=pathlib.Path({str(release)!r})\n"
                  "while not release.exists(): time.sleep(0.01)\n"
                  "print('stderr output', file=sys.stderr, flush=True)\n")
        process = subprocess.Popen(self.command(source), env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            readable, _, _ = select.select([process.stdout], [], [], 5)
            self.assertTrue(readable, "Build output must arrive before the command finishes")
            self.assertEqual(process.stdout.readline(), b"ready\n")
            self.assertIsNone(process.poll())
            release.touch()
            output, errors = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(output, b"stderr output\n")
            self.assertEqual(errors, b"")
        finally:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=10)

    def test_raw_log_preserves_bytes_and_formatter_arguments(self):
        import json
        self.formatter()
        log = self.root / "raw build.log"
        args = self.root / "formatter.json"
        self.env.update(TEST_RAW_LOG=str(log), FORMAT_ARGS=str(args), GITHUB_ACTIONS="true")
        result = self.run_source("import os; os.write(1, b'output\\r\\n\\xff'); os.write(2, b'error\\n')")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_bytes(), b"output\r\n\xfferror\n")
        self.assertEqual(result.stdout, log.read_bytes())
        self.assertEqual(json.loads(args.read_text()), ["--renderer", "github-actions"])

    def test_every_pipeline_failure_is_reported(self):
        self.formatter()
        for build_status, formatter_status, expected in ((65, 0, 65), (0, 42, 42), (65, 42, 42)):
            with self.subTest(build=build_status, formatter=formatter_status):
                self.env["FORMAT_EXIT"] = str(formatter_status)
                result = self.run_source(f"import sys; print('build'); sys.exit({build_status})")
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_unwritable_log_fails_without_creating_parent(self):
        self.formatter()
        log = self.root / "missing" / "build.log"
        self.env["TEST_RAW_LOG"] = str(log)
        result = self.run_source("print('build output')")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"build output\n")
        self.assertFalse(log.parent.exists())

    def test_plain_command_keeps_output_streams_separate(self):
        self.formatter()
        self.env["FORMAT_EXIT"] = "42"
        result = self.run_source("import sys; print('out'); print('err', file=sys.stderr)", "command")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"out\n")
        self.assertEqual(result.stderr, b"err\n")

    def test_cancellation_stops_command_and_its_descendant(self):
        # Exercise both the simple command and build pipeline; the child acknowledges SIGTERM
        # through a file so this assertion does not confuse a short-lived zombie with a live tool.
        for mode in ("command", "build"):
            with self.subTest(mode=mode):
                self.formatter()
                ready = self.root / f"{mode}-ready"
                stopped = self.root / f"{mode}-stopped"
                child = self.root / f"{mode}-child.py"
                child.write_text(textwrap.dedent(f'''\
                    import pathlib, signal, time
                    def stop(*_):
                        pathlib.Path({str(stopped)!r}).touch()
                        raise SystemExit(0)
                    signal.signal(signal.SIGTERM, stop)
                    pathlib.Path({str(ready)!r}).touch()
                    while True: time.sleep(0.01)
                '''))
                parent = (f"import subprocess, sys; "
                          f"child=subprocess.Popen([sys.executable, {str(child)!r}]); child.wait()")
                process = subprocess.Popen(self.command(parent, mode), env=self.env,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    deadline = time.monotonic() + 5
                    while not ready.exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(ready.exists(), "Child did not start")
                    process.send_signal(signal.SIGTERM)
                    _, errors = process.communicate(timeout=10)
                    self.assertEqual(process.returncode, 143, errors)
                    self.assertTrue(stopped.exists(), "Descendant did not receive cancellation")
                finally:
                    if process.poll() is None:
                        process.terminate()
                    process.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
