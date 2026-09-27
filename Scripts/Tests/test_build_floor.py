#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import tomllib
import unittest


SCRIPTS = pathlib.Path(__file__).parents[1]
SCRIPT = SCRIPTS / "build-floor.py"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("build_floor", SCRIPT)
BUILD_FLOOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_FLOOR)


class FloorBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="floor test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        shutil.copyfile(SCRIPT, self.root / "Scripts/build-floor.py")
        shutil.copyfile(SCRIPTS / "build_support.py", self.root / "Scripts/build_support.py")
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
                        "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS", "GROVE_EXCLUDE_DOCC_CATALOGS", "PWD"
                    )
                }}) + "\\n")
            attempts = pathlib.Path("manifest-attempts")
            count = int(attempts.read_text()) + 1 if attempts.exists() else 1
            attempts.write_text(str(count))
            if count <= int(os.environ.get("FLOOR_TEST_MANIFEST_FAILURES", "0")):
                print("incomplete manifest")
                print(f"manifest failure {count}", file=sys.stderr)
                sys.exit(42)
            print(pathlib.Path("dump.json").read_text())
        ''')
        self.write_stub("xcodebuild", '''
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["FLOOR_TEST_LOG"], "a") as log:
                log.write(json.dumps({"tool": "xcodebuild", "args": args, "env": {
                    key: os.environ.get(key) for key in (
                        "GROVE_FLOOR_BUILD_TARGETS", "GROVE_LOWERED_DEPLOYMENT_TARGETS",
                        "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS", "GROVE_EXCLUDE_DOCC_CATALOGS", "PWD"
                    )
                }}) + "\\n")
            products = pathlib.Path(args[args.index("-derivedDataPath") + 1]) / "Build/Products/Debug"
            products.mkdir(parents=True, exist_ok=True)
            for module in os.environ["FLOOR_TEST_MODULES"].split(","):
                if module:
                    (products / f"{module}.swiftmodule").mkdir(exist_ok=True)
            if module := os.environ.get("FLOOR_TEST_SYMLINK_MODULE"):
                previous_module = pathlib.Path("previous-module.swiftmodule")
                previous_module.mkdir(exist_ok=True)
                (products / f"{module}.swiftmodule").symlink_to(previous_module.resolve(), target_is_directory=True)
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

    def run_build(self, platform="iOS", kind="simulator", modules=None, build_exit=0, manifest_failures=0, symlink_module=""):
        environment = {
            **os.environ,
            "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
            "FLOOR_TEST_MANIFEST_FAILURES": str(manifest_failures),
            "FLOOR_TEST_LOG": str(self.log),
            "FLOOR_TEST_MODULES": ",".join(sorted(self.modules(platform) if modules is None else modules)),
            "FLOOR_TEST_BUILD_EXIT": str(build_exit),
            "FLOOR_TEST_SYMLINK_MODULE": symlink_module,
            "RUNNER_TEMP": str(self.root / "runner-temp"),
            # The script must override these inherited values before inspecting the manifest.
            "GROVE_FLOOR_BUILD_TARGETS": "InheritedTarget",
            "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS": "1",
            "GROVE_LOWERED_DEPLOYMENT_TARGETS": "0",
            "GROVE_EXCLUDE_DOCC_CATALOGS": "0",
            "PWD": "/unrelated/inherited/directory",
        }
        self.log.write_text("")
        result = subprocess.run(
            [sys.executable, "Scripts/build-floor.py", platform, kind], cwd=self.root, env=environment,
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
            self.assertEqual(call["env"]["GROVE_EXCLUDE_DOCC_CATALOGS"], "1")
            self.assertEqual(pathlib.Path(call["env"]["PWD"]), self.root.resolve())

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

    def test_symlink_to_old_module_does_not_satisfy_coverage(self):
        result, _ = self.run_build(modules=self.modules("iOS") - {"Base"}, symlink_module="Base")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("coverage gap", result.stdout)
        self.assertIn("Base", result.stdout)

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
        for args in (first_args, second_args):
            output = pathlib.Path(args[args.index("-derivedDataPath") + 1])
            self.assertTrue((output / "package.json").is_file(), "Retain diagnostics until normal cleanup")

    def test_manifest_failure_retries_without_leaking_first_diagnostic_or_partial_json(self):
        result, calls = self.run_build(manifest_failures=1)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call["tool"] for call in calls], ["swift", "swift", "xcodebuild"])
        self.assertNotIn("manifest failure 1", result.stderr)
        build_args = calls[-1]["args"]
        output = pathlib.Path(build_args[build_args.index("-derivedDataPath") + 1])
        self.assertEqual(json.loads((output / "package.json").read_text()), json.loads((self.root / "dump.json").read_text()))

    def test_repeated_manifest_failure_stops_before_build_and_shows_retry_error(self):
        result, calls = self.run_build(manifest_failures=2)

        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertEqual([call["tool"] for call in calls], ["swift", "swift"])
        self.assertNotIn("manifest failure 1", result.stderr)
        self.assertIn("manifest failure 2", result.stderr)

    def graph(self):
        manifest = json.loads((self.root / "dump.json").read_text())
        with (self.root / "packages.toml").open("rb") as source:
            packages = tomllib.load(source)
        return manifest, packages

    def test_selection_follows_added_and_removed_package_without_script_changes(self):
        manifest, packages = self.graph()
        original_products, original_modules = BUILD_FLOOR.select_products(manifest, packages, "iOS")
        manifest["targets"].append({"name": "NewConsumer", "dependencies": [{"byName": ["Facade", None]}]})
        manifest["products"].append({
            "name": "NewLibrary", "targets": ["NewConsumer"], "type": {"library": ["automatic"]},
        })
        packages["NewPackage"] = {"platforms": ["iOS"], "targets": ["NewConsumer"]}

        products, modules = BUILD_FLOOR.select_products(manifest, packages, "iOS")
        self.assertEqual(set(products), (set(original_products) - {"FacadeLibrary"}) | {"NewLibrary"})
        self.assertEqual(set(modules), set(original_modules) | {"NewConsumer"})
        watch_products, watch_modules = BUILD_FLOOR.select_products(manifest, packages, "watchOS")
        self.assertNotIn("NewLibrary", watch_products)
        self.assertNotIn("NewConsumer", watch_modules)

        manifest["targets"] = [target for target in manifest["targets"] if target["name"] != "NewConsumer"]
        manifest["products"] = [product for product in manifest["products"] if product["name"] != "NewLibrary"]
        del packages["NewPackage"]
        self.assertEqual(BUILD_FLOOR.select_products(manifest, packages, "iOS"), (original_products, original_modules))

    def test_selection_follows_changed_dependencies_and_disabled_traits(self):
        manifest, packages = self.graph()
        targets = {target["name"]: target for target in manifest["targets"]}
        original_products, original_modules = BUILD_FLOOR.select_products(manifest, packages, "iOS")
        self.assertNotIn("BaseLibrary", original_products)
        self.assertIn("OptionalSupportLibrary", original_products)

        # Removing the Facade -> Base edge makes Base a top-level product.
        # Its replacement is unconditional, so OptionalSupport is now covered
        # transitively instead of appearing separately in the aggregate.
        targets["Facade"]["dependencies"] = [{"target": ["OptionalSupport", None]}]
        products, modules = BUILD_FLOOR.select_products(manifest, packages, "iOS")
        self.assertEqual(set(products), (set(original_products) - {"OptionalSupportLibrary"}) | {"BaseLibrary"})
        self.assertEqual(modules, original_modules)

    def test_selection_follows_changed_external_platform_requirement_transitively(self):
        manifest, packages = self.graph()
        targets = {target["name"]: target for target in manifest["targets"]}
        products, modules = BUILD_FLOOR.select_products(manifest, packages, "watchOS")
        self.assertNotIn("FHIRFacadeLibrary", products)
        self.assertNotIn("FHIR", modules)
        self.assertNotIn("FHIRFacade", modules)

        targets["FHIR"]["dependencies"][0]["product"][3]["platformNames"].append("watchos")
        updated_products, updated_modules = BUILD_FLOOR.select_products(manifest, packages, "watchOS")
        self.assertEqual(set(updated_products), set(products) | {"FHIRFacadeLibrary"})
        self.assertEqual(set(updated_modules), set(modules) | {"FHIR", "FHIRFacade"})


if __name__ == "__main__":
    unittest.main()
