#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

"""Stream build commands and stop their child processes when a script is cancelled."""

import contextlib
import os
import shutil
import signal
import subprocess
import sys
import time


class Interrupted(BaseException):
    def __init__(self, signum):
        self.signum = signum


def _interrupt(signum, _frame):
    raise Interrupted(signum)


def _stop_processes(processes):
    # Each pipeline stage has its own process group, including any tools it launches. Signal the
    # group even when its leader exited: compilers may still be running or holding a pipe open.
    handlers = {signum: signal.signal(signum, signal.SIG_IGN)
                for signum in (signal.SIGINT, signal.SIGTERM)}
    try:
        for process in processes:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
        deadline = time.monotonic() + 5
        for process in processes:
            with contextlib.suppress(subprocess.TimeoutExpired):
                process.wait(timeout=max(0, deadline - time.monotonic()))
        for process in processes:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    finally:
        for signum, handler in handlers.items():
            signal.signal(signum, handler)


def _pipeline(commands, *, env=None, stdout=None, stderr=None):
    processes = []
    completed = False
    previous_output = None
    try:
        for index, command in enumerate(commands):
            process = subprocess.Popen(
                command,
                stdin=previous_output,
                stdout=subprocess.PIPE if index < len(commands) - 1 else stdout,
                stderr=stderr if index == 0 else None,
                env=env,
                start_new_session=True,
            )
            processes.append(process)
            if previous_output is not None:
                previous_output.close()
            previous_output = process.stdout
        statuses = [process.wait() for process in processes]
        completed = True
        # Match Bash pipefail: a formatter or tee failure must not hide a failed build, and a
        # successful formatter must not hide a failed compiler. Return the last failing stage.
        status = next((status for status in reversed(statuses) if status), 0)
        return 128 - status if status < 0 else status
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return 127 if isinstance(error, FileNotFoundError) else 126
    finally:
        if previous_output is not None:
            previous_output.close()
        if not completed:
            _stop_processes(processes)


def run_command(args, *, env=None, stdout=None, stderr=None):
    """Run a command without a shell and return its exit status."""
    return _pipeline([args], env=env, stdout=stdout, stderr=stderr)


def run_build(args, *, env=None, log_path=None):
    """Stream merged build output, optionally retaining a raw log and running xcbeautify.

    Direct pipes preserve bytes and keep memory bounded even for very large Xcode logs. Keeping
    tee as a separate process also preserves its failure behavior when the log cannot be written.
    """
    environment = os.environ if env is None else env
    commands = [args]
    if log_path is not None:
        commands.append(["tee", str(log_path)])
    formatter = shutil.which("xcbeautify", path=environment.get("PATH"))
    if formatter:
        commands.append([formatter])
        if environment.get("GITHUB_ACTIONS"):
            commands[-1].extend(["--renderer", "github-actions"])
    return _pipeline(commands, env=env, stderr=subprocess.STDOUT)


def run_cli(main):
    """Run a script entry point with cancellation and concise command-line errors."""
    sys.stdout.reconfigure(line_buffering=True)
    previous_handlers = {
        signum: signal.signal(signum, _interrupt)
        for signum in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        status = main()
    except Interrupted as error:
        status = 128 + error.signum
    except KeyboardInterrupt:
        status = 130
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        status = 1
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    sys.exit(status)
