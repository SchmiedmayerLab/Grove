#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
# SPDX-License-Identifier: MIT
#

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LinuxTestRunnerTests(unittest.TestCase):
    def run_package(self, package, failing_target=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Scripts").mkdir()
            shutil.copy2(ROOT / "Scripts/run-package-tests.sh", root / "Scripts/run-package-tests.sh")
            shutil.copy2(ROOT / "packages.toml", root / "packages.toml")
            binaries = root / "bin"
            binaries.mkdir()
            commands = {
                "uname": "#!/bin/sh\nprintf 'Linux\\n'\n",
                "swift": """#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ["--version"]:
    print("Swift test double")
    sys.exit(0)
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("FAILING_TARGET") in sys.argv[1:]:
    sys.exit(23)
""",
            }
            for name in ("xcodebuild", "xcrun", "sw_vers"):
                commands[name] = "#!/bin/sh\necho 'Apple-only command invoked' >&2\nexit 99\n"
            for name, source in commands.items():
                executable = binaries / name
                executable.write_text(source)
                executable.chmod(0o755)
            log = root / "commands.jsonl"
            env = dict(os.environ, PATH=f"{binaries}{os.pathsep}{os.environ['PATH']}",
                       COMMAND_LOG=str(log), FAILING_TARGET=failing_target)
            result = subprocess.run(
                ["bash", "Scripts/run-package-tests.sh", package, "Linux"],
                cwd=root, env=env, capture_output=True, text=True, timeout=30,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_linux_builds_only_the_configured_targets_with_native_engine(self):
        packages = {
            "GroveHealthKit": ["GroveHealthKitTests"],
            "GroveStudy": ["GroveStudyTests"],
            "GroveLLM": ["GroveLLM", "GeneratedOpenAIClient", "GroveLLMOpenAI", "GroveLLMAnthropic", "GroveLLMGemini"],
        }
        for package, targets in packages.items():
            with self.subTest(package=package):
                result, calls = self.run_package(package)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls, [["build", "--build-system", "native", "--target", target] for target in targets])

    def test_failed_linux_target_fails_the_job_without_building_later_targets(self):
        result, calls = self.run_package("GroveLLM", failing_target="GroveLLM")

        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
