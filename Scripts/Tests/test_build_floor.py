#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "build-floor.sh"


class FloorBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        shutil.copyfile(SCRIPT, self.root / "Scripts/build-floor.sh")
        (self.root / "bin").mkdir()
        self.log = self.root / "calls.jsonl"
        targets = [
            {"name": "Base", "dependencies": []},
            {"name": "Facade", "dependencies": [
                {"target": ["Base", None]},
                {"target": ["OptionalSupport", {"traits": ["OptionalFeature"]}]},
            ]},
            {"name": "OptionalSupport", "dependencies": []},
            {"name": "FHIR", "dependencies": [
                {"product": ["FHIRModels", "fhir", None, {"platformNames": ["ios", "macos"]}]},
            ]},
            {"name": "FHIRFacade", "dependencies": [{"target": ["FHIR", None]}]},
            {"name": "Mobile", "dependencies": []},
            {"name": "XCTGroveNotifications", "dependencies": []},
        ]
        products = [
            {"name": f"{target['name']}Library", "targets": [target["name"]], "type": {"library": ["automatic"]}}
            for target in targets[:-1]
        ]
        products.append({
            "name": "XCTGroveNotifications", "targets": ["XCTGroveNotifications"],
            "type": {"library": ["automatic"]},
        })
        (self.root / "dump.json").write_text(json.dumps({
            "products": products,
            "targets": targets,
            "platforms": [
                {"platformName": "ios", "version": "15.0"},
                {"platformName": "macos", "version": "12.0"},
                {"platformName": "watchos", "version": "9.0"},
            ],
        }))
        (self.root / "packages.toml").write_text(textwrap.dedent('''\
            [Common]
            platforms = ["iOS", "macOS", "watchOS"]
            targets = ["Base", "Facade", "OptionalSupport", "FHIR", "FHIRFacade", "XCTGroveNotifications"]
            [Mobile]
            platforms = ["iOS"]
            targets = ["Mobile"]
        '''))
        self.write_stub("swift", '''
            import json, os, pathlib, sys
            with open(os.environ["FLOOR_TEST_LOG"], "a") as log:
                log.write(json.dumps({"tool": "swift", "args": sys.argv[1:], "env": {
                    key: os.environ.get(key) for key in (
                        "GROVE_FLOOR_BUILD_TARGETS", "GROVE_LOWERED_DEPLOYMENT_TARGETS",
                        "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"
                    )
                }}) + "\\n")
            print(pathlib.Path("dump.json").read_text())
        ''')
        self.write_stub("xcodebuild", '''
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["FLOOR_TEST_LOG"], "a") as log:
                log.write(json.dumps({"tool": "xcodebuild", "args": args, "env": {
                    key: os.environ.get(key) for key in (
                        "GROVE_FLOOR_BUILD_TARGETS", "GROVE_LOWERED_DEPLOYMENT_TARGETS",
                        "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"
                    )
                }}) + "\\n")
            products = pathlib.Path(args[args.index("-derivedDataPath") + 1]) / "Build/Products/Debug"
            products.mkdir(parents=True, exist_ok=True)
            for module in os.environ["FLOOR_TEST_MODULES"].split(","):
                if module:
                    (products / f"{module}.swiftmodule").mkdir(exist_ok=True)
            sys.exit(int(os.environ.get("FLOOR_TEST_BUILD_EXIT", "0")))
        ''')
        # Avoid depending on whether the developer machine has xcbeautify installed.
        self.write_stub("xcbeautify", '''
            import shutil, sys
            shutil.copyfileobj(sys.stdin, sys.stdout)
        ''')

    def write_stub(self, name, source):
        path = self.root / "bin" / name
        path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(source))
        path.chmod(0o755)

    def modules(self, platform):
        modules = {"Base", "Facade", "OptionalSupport"}
        if platform != "watchOS":
            modules.update(("FHIR", "FHIRFacade"))
        if platform == "iOS":
            modules.update(("Mobile", "XCTGroveNotifications"))
        return modules

    def run_build(self, platform="iOS", kind="simulator", modules=None, build_exit=0):
        environment = {
            **os.environ,
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "RUNNER_TEMP": str(self.root / "runner-temp"),
            "FLOOR_TEST_LOG": str(self.log),
            "FLOOR_TEST_MODULES": ",".join(sorted(self.modules(platform) if modules is None else modules)),
            "FLOOR_TEST_BUILD_EXIT": str(build_exit),
            "RUNNER_TEMP": str(self.root / "runner-temp"),
            # The script must override these inherited values before inspecting the manifest.
            "GROVE_FLOOR_BUILD_TARGETS": "InheritedTarget",
            "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS": "1",
            "GROVE_LOWERED_DEPLOYMENT_TARGETS": "0",
        }
        self.log.write_text("")
        result = subprocess.run(
            ["/bin/bash", "Scripts/build-floor.sh", platform, kind], cwd=self.root, env=environment,
            capture_output=True, text=True, timeout=20,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def test_one_aggregate_build_selects_target_names_and_preserves_floor_configuration(self):
        result, calls = self.run_build()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call["tool"] for call in calls], ["swift", "xcodebuild"])
        self.assertIsNone(calls[0]["env"]["GROVE_FLOOR_BUILD_TARGETS"])
        build = calls[1]
        self.assertEqual(build["args"][build["args"].index("-scheme") + 1], "GroveDeploymentFloor")
        self.assertEqual(set(build["env"]["GROVE_FLOOR_BUILD_TARGETS"].split(",")), {
            "Facade", "OptionalSupport", "FHIRFacade", "Mobile", "XCTGroveNotifications",
        })
        for call in calls:
            self.assertEqual(call["env"]["GROVE_LOWERED_DEPLOYMENT_TARGETS"], "1")
            self.assertIsNone(call["env"]["GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"])

    def test_platform_selection_and_simulator_architecture(self):
        for platform, kind, destination in (
            ("iOS", "simulator", "generic/platform=iOS Simulator"),
            ("iOS", "device", "generic/platform=iOS"),
            ("watchOS", "simulator", "generic/platform=watchOS Simulator"),
            ("watchOS", "device", "generic/platform=watchOS"),
            ("macOS", "simulator", "platform=macOS,arch=arm64"),
        ):
            with self.subTest(platform=platform, kind=kind):
                result, calls = self.run_build(platform, kind)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                builds = [call for call in calls if call["tool"] == "xcodebuild"]
                self.assertEqual(len(builds), 1)
                args = builds[0]["args"]
                self.assertEqual(args[args.index("-destination") + 1], destination)
                architecture = [arg for arg in args if arg.startswith("ARCHS=")]
                self.assertEqual(architecture, ["ARCHS=arm64"] if platform != "macOS" and kind == "simulator" else [])
                excluded = [arg for arg in args if arg.startswith("EXCLUDED_ARCHS=")]
                self.assertEqual(excluded, ["EXCLUDED_ARCHS=x86_64"])
                selected = set(builds[0]["env"]["GROVE_FLOOR_BUILD_TARGETS"].split(","))
                expected = self.modules(platform) - {"Base", "FHIR"}
                self.assertEqual(selected, expected)

    def test_successful_build_with_missing_module_fails_coverage(self):
        result, _ = self.run_build(modules=self.modules("iOS") - {"Base"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("coverage gap", result.stdout)
        self.assertIn("Base", result.stdout)

    def test_build_failure_is_reported_even_if_all_modules_exist(self):
        result, _ = self.run_build(build_exit=65)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("floor build FAILED", result.stdout)

    def test_previous_run_modules_cannot_satisfy_current_coverage(self):
        first, first_calls = self.run_build()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        second, second_calls = self.run_build(modules=self.modules("iOS") - {"Base"})

        self.assertNotEqual(second.returncode, 0)
        self.assertIn("coverage gap", second.stdout)
        first_args = first_calls[-1]["args"]
        second_args = second_calls[-1]["args"]
        self.assertNotEqual(
            first_args[first_args.index("-derivedDataPath") + 1],
            second_args[second_args.index("-derivedDataPath") + 1],
        )


if __name__ == "__main__":
    unittest.main()
