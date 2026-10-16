#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


SCRIPTS = Path(__file__).parents[1]


class DocumentationBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="documentation tests ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "Scripts").mkdir()
        for name in ("build-documentation.py", "build_support.py"):
            shutil.copyfile(SCRIPTS / name, self.root / "Scripts" / name)
        (self.root / "bin").mkdir()
        self.calls_path = self.root / "calls.jsonl"
        self.runner_temp = self.root / "runner temp"
        self.derived_data = self.runner_temp / "grove-docs-derivedData"
        self.output = self.runner_temp / "grove-documentation"
        (self.root / ".spi.yml").write_text("documentation_targets: [Alpha, Beta]\n")
        self.write_stub("xcodebuild", '''
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["DOCS_TEST_CALLS"], "a") as log:
                log.write(json.dumps({"tool": "xcodebuild", "args": args, "env": {
                    key: os.environ.get(key) for key in (
                        "GROVE_LOWERED_DEPLOYMENT_TARGETS", "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS",
                        "GROVE_EXCLUDE_DOCC_CATALOGS", "LLVM_PROFILE_FILE", "PWD"
                    )
                }}) + "\\n")
            products = pathlib.Path(args[args.index("-derivedDataPath") + 1]) / "Build/Products"
            products.mkdir(parents=True, exist_ok=True)
            for target, subdir in json.loads(os.environ["DOCS_TEST_ARCHIVES"]).items():
                (products / subdir / f"{target}.doccarchive").mkdir(parents=True, exist_ok=True)
            print("raw stdout", flush=True)
            print(os.environ.get("DOCS_TEST_DIAGNOSTICS", "raw stderr"), file=sys.stderr, flush=True)
            sys.exit(int(os.environ.get("DOCS_TEST_BUILD_EXIT", "0")))
        ''')
        self.write_stub("xcrun", '''
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["DOCS_TEST_CALLS"], "a") as log:
                log.write(json.dumps({"tool": "xcrun", "args": args}) + "\\n")
            output = pathlib.Path(args[args.index("--output-path") + 1])
            output.mkdir(parents=True, exist_ok=True)
            (output / "generated").write_text("retain this output even on failure")
            variable = "DOCS_TEST_MERGE_EXIT" if args[1] == "merge" else "DOCS_TEST_TRANSFORM_EXIT"
            sys.exit(int(os.environ.get(variable, "0")))
        ''')
        self.write_stub("xcbeautify", '''
            import json, os, pathlib, sys
            pathlib.Path(os.environ["DOCS_TEST_FORMATTER_ARGS"]).write_text(json.dumps(sys.argv[1:]))
            for line in sys.stdin:
                print("formatted: " + line, end="", flush=True)
            sys.exit(int(os.environ.get("DOCS_TEST_FORMATTER_EXIT", "0")))
        ''')

    def write_stub(self, name, source):
        path = self.root / "bin" / name
        path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(source))
        path.chmod(0o755)

    def run_build(self, **overrides):
        env = {key: value for key, value in os.environ.items() if not key.startswith((
            "DOC_", "DOCS_TEST_", "GROVE_", "LLVM_PROFILE_",
        )) and key not in ("RUNNER_TEMP", "DERIVED_DATA_PATH", "COMBINED_ARCHIVE", "STATIC_ARCHIVE", "GITHUB_ACTIONS")}
        env.update({
            # Avoid inheriting the developer's xcbeautify or Xcode executables.
            "PATH": f"{self.root / 'bin'}:/usr/bin:/bin",
            "RUNNER_TEMP": str(self.runner_temp),
            "DOCS_TEST_CALLS": str(self.calls_path),
            "DOCS_TEST_ARCHIVES": json.dumps({"Alpha": "Debug", "Beta": "Debug"}),
            "DOCS_TEST_FORMATTER_ARGS": str(self.root / "formatter.json"),
            "GROVE_LOWERED_DEPLOYMENT_TARGETS": "1",
            "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS": "",
            "GROVE_EXCLUDE_DOCC_CATALOGS": "1",
            "PWD": "/unrelated/inherited/directory",
        })
        env.update(overrides)
        self.calls_path.write_text("")
        # The CLI must locate the repository even when invoked elsewhere.
        result = subprocess.run(
            [sys.executable, str(self.root / "Scripts/build-documentation.py")],
            cwd=self.root.parent, env=env, capture_output=True, text=True, timeout=20,
        )
        calls = [json.loads(line) for line in self.calls_path.read_text().splitlines()]
        return result, calls

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_success_builds_declared_targets_and_packages_both_archives(self):
        result, calls = self.run_build(GITHUB_ACTIONS="true")
        self.assert_success(result)
        self.assertEqual([call["tool"] for call in calls], ["xcodebuild", "xcrun", "xcrun"])
        self.assertEqual(calls[0]["args"], [
            "-scheme", "Grove-Package", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(self.derived_data), "-skipPackageUpdates",
            "-skipPackagePluginValidation", "-skipMacroValidation", "ARCHS=arm64",
            "IPHONEOS_DEPLOYMENT_TARGET=18.0", "docbuild",
        ])
        self.assertEqual(calls[0]["env"], {
            "GROVE_LOWERED_DEPLOYMENT_TARGETS": "0", "GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS": "1",
            "GROVE_EXCLUDE_DOCC_CATALOGS": "0", "LLVM_PROFILE_FILE": str(self.output / "default-%p.profraw"),
            "PWD": str(self.root),
        })
        combined = str(self.output / "Grove.doccarchive")
        self.assertEqual(calls[1]["args"], [
            "docc", "merge", str(self.derived_data / "Build/Products/Debug/Alpha.doccarchive"),
            str(self.derived_data / "Build/Products/Debug/Beta.doccarchive"),
            "--output-path", combined, "--synthesized-landing-page-name", "Grove",
            "--synthesized-landing-page-kind", "Package", "--synthesized-landing-page-topics-style", "compactGrid",
        ])
        self.assertEqual(calls[2]["args"], [
            "docc", "process-archive", "transform-for-static-hosting", combined,
            "--output-path", str(self.output / "Grove-static.doccarchive"), "--hosting-base-path", "/Grove",
        ])
        self.assertEqual(json.loads((self.root / "formatter.json").read_text()), ["--renderer", "github-actions"])
        self.assertEqual((self.output / "docbuild.log").read_text(), "raw stdout\nraw stderr\n")
        self.assertIn("formatted: raw stderr", result.stdout)

    def test_environment_overrides_preserve_paths_with_spaces_and_explicit_trait_setting(self):
        custom = self.root / "custom output"
        custom.mkdir()
        result, calls = self.run_build(
            DERIVED_DATA_PATH=str(self.root / "custom derived"), DOC_OUTPUT_DIR=str(custom),
            DOC_SCHEME="Custom Package", DOC_DESTINATION="platform=macOS,arch=arm64",
            DOC_DEPLOYMENT_TARGET="19.0", DOC_LOG_PATH=str(custom / "raw log.txt"),
            COMBINED_ARCHIVE=str(custom / "combined docs"), STATIC_ARCHIVE=str(custom / "static docs"),
            DOC_HOSTING_BASE_PATH="/custom site", GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS="0",
            LLVM_PROFILE_FILE="custom-%p.profraw",
        )
        self.assert_success(result)
        self.assertEqual(calls[0]["args"][1], "Custom Package")
        self.assertEqual(calls[0]["args"][3], "platform=macOS,arch=arm64")
        self.assertEqual(calls[0]["args"][5], str(self.root / "custom derived"))
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET=19.0", calls[0]["args"])
        self.assertEqual(calls[0]["env"]["GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS"], "0")
        self.assertEqual(calls[0]["env"]["LLVM_PROFILE_FILE"], "custom-%p.profraw")
        self.assertIn(str(custom / "combined docs"), calls[1]["args"])
        self.assertEqual(calls[2]["args"][-3:], [str(custom / "static docs"), "--hosting-base-path", "/custom site"])
        self.assertTrue((custom / "raw log.txt").exists())
        self.assertEqual(json.loads((self.root / "formatter.json").read_text()), [])

    def test_empty_overrides_use_local_defaults_without_runner_temp(self):
        result, calls = self.run_build(**dict.fromkeys((
            "RUNNER_TEMP", "DERIVED_DATA_PATH", "DOC_OUTPUT_DIR", "DOC_SCHEME", "DOC_DESTINATION",
            "DOC_DEPLOYMENT_TARGET", "DOC_LOG_PATH", "COMBINED_ARCHIVE", "STATIC_ARCHIVE",
            "DOC_HOSTING_BASE_PATH", "LLVM_PROFILE_FILE",
        ), ""))
        self.assert_success(result)
        self.assertEqual(calls[0]["args"][5], ".derivedData-docs")
        self.assertEqual(calls[0]["args"][1], "Grove-Package")
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET=18.0", calls[0]["args"])
        self.assertEqual(calls[2]["args"][-1], "/Grove")
        self.assertTrue((self.root / ".build/documentation/docbuild.log").exists())

    def test_changed_block_targets_drive_archive_selection_in_declared_order(self):
        (self.root / ".spi.yml").write_text(textwrap.dedent('''\
            builds:
              - documentation_targets:
                  - 'NewTarget'
                  # blank and comment lines are allowed

                  - "Alpha"
                platform: ios
              - documentation_targets: [Ignored]
        '''))
        result, calls = self.run_build(DOCS_TEST_ARCHIVES=json.dumps({"Alpha": "Debug", "NewTarget": "Debug"}))
        self.assert_success(result)
        self.assertEqual([Path(arg).stem for arg in calls[1]["args"][2:4]], ["NewTarget", "Alpha"])

    def test_missing_or_empty_target_list_stops_before_building(self):
        for contents in ("builds: []", "documentation_targets: []", "documentation_targets:\nplatform: ios"):
            with self.subTest(contents=contents):
                (self.root / ".spi.yml").write_text(contents)
                result, calls = self.run_build()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Could not find documentation_targets", result.stderr)
                self.assertEqual(calls, [])

    def test_repository_swift_comment_and_catalog_warnings_fail_before_merge(self):
        for relative, message in (
            ("Sources/Alpha/Alpha.docc/Page.md", "unexpected catalog issue"),
            ("Sources/Alpha/File.swift", "'Thing' doesn't exist at '/Alpha'"),
            ("Sources/Alpha/File.swift", "'Thing' is ambiguous at '/Alpha'"),
            ("Sources/Alpha/File.swift", "'Thing' isn't a disambiguation for '/Alpha'"),
            ("Sources/Alpha/File.swift", "comment used to document parameter missing"),
            ("Sources/Alpha/File.swift", "Parameter 'value' does not exist"),
            ("Sources/Alpha/File.swift", "Symbol not found in scope"),
        ):
            with self.subTest(message=message):
                diagnostic = f"{self.root / relative}:1:2: warning: {message}"
                result, calls = self.run_build(DOCS_TEST_DIAGNOSTICS=diagnostic)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Documentation warnings from this repository:", result.stdout)
                self.assertIn(diagnostic, (self.output / "docbuild.log").read_text())
                self.assertEqual(len(calls), 1)

    def test_dependency_and_ordinary_compiler_warnings_do_not_fail_docs(self):
        diagnostics = [
            f"{self.root / 'Sources/Alpha/File.swift'}:1: warning: deprecated declaration",
            f"{self.root / '.build/checkouts/A/Sources/A.docc/Page.md'}:1: warning: missing topic",
            f"{self.root / '.derivedData-docs/Source.swift'}:1: warning: Symbol not found in scope",
            f"{self.root / 'nested/SourcePackages/A/Sources/A.docc/Page.md'}:1: warning: missing topic",
            "/external/Sources/Other.docc/Page.md:1: warning: missing topic",
        ]
        result, calls = self.run_build(DOCS_TEST_DIAGNOSTICS="\n".join(diagnostics))
        self.assert_success(result)
        self.assertEqual(len(calls), 3)

    def test_unlocated_docc_warnings_fail_and_are_deduplicated_in_summary(self):
        result, calls = self.run_build(DOCS_TEST_DIAGNOSTICS="warning: broken catalog\n  warning: broken catalog")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.split("Documentation warnings from this repository:\n")[1], "warning: broken catalog\n")
        self.assertEqual(len(calls), 1)

    def test_archive_search_accepts_depth_three_and_rejects_depth_four(self):
        result, _ = self.run_build(DOCS_TEST_ARCHIVES=json.dumps({"Alpha": "one/two", "Beta": "one/two"}))
        self.assert_success(result)
        shutil.rmtree(self.derived_data)
        result, calls = self.run_build(DOCS_TEST_ARCHIVES=json.dumps({"Alpha": "one/two", "Beta": "one/two/three"}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing DocC archives for targets:\n  Beta", result.stderr)
        self.assertEqual(len(calls), 1)

    def test_directory_symlink_cannot_satisfy_required_archive(self):
        products = self.derived_data / "Build/Products"
        products.mkdir(parents=True)
        external = self.root / "external archive"
        external.mkdir()
        (products / "Beta.doccarchive").symlink_to(external, target_is_directory=True)
        result, calls = self.run_build(DOCS_TEST_ARCHIVES=json.dumps({"Alpha": "Debug"}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("  Beta", result.stderr)
        self.assertEqual(len(calls), 1)

    def test_failed_build_cleans_only_old_final_archives_and_retains_failure_output(self):
        for name in ("Grove.doccarchive", "Grove-static.doccarchive", "unrelated"):
            path = self.output / name
            path.mkdir(parents=True)
            (path / "old").write_text("old")
        result, calls = self.run_build(DOCS_TEST_BUILD_EXIT="65")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Documentation build failed", result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertFalse((self.output / "Grove.doccarchive").exists())
        self.assertFalse((self.output / "Grove-static.doccarchive").exists())
        self.assertTrue((self.output / "unrelated/old").exists())
        self.assertTrue((self.output / "docbuild.log").exists())
        self.assertTrue((self.derived_data / "Build/Products/Debug/Alpha.doccarchive").exists())

    def test_old_archive_symlink_is_removed_without_deleting_its_target(self):
        self.output.mkdir(parents=True)
        external = self.root / "external"
        external.mkdir()
        (external / "keep").write_text("keep")
        (self.output / "Grove.doccarchive").symlink_to(external, target_is_directory=True)
        (self.output / "Grove-static.doccarchive").write_text("old file")
        result, _ = self.run_build()
        self.assert_success(result)
        self.assertTrue((external / "keep").exists())
        self.assertFalse((self.output / "Grove.doccarchive").is_symlink())

    def test_merge_and_transform_failures_preserve_partial_outputs(self):
        for variable, count, archive in (
            ("DOCS_TEST_MERGE_EXIT", 2, "Grove.doccarchive"),
            ("DOCS_TEST_TRANSFORM_EXIT", 3, "Grove-static.doccarchive"),
        ):
            with self.subTest(variable=variable):
                result, calls = self.run_build(**{variable: "7"})
                self.assertEqual(result.returncode, 7)
                self.assertEqual(len(calls), count)
                self.assertTrue((self.output / archive / "generated").exists())
                self.assertNotIn("Built static-hosting DocC archive", result.stdout)

    def test_no_formatter_still_streams_and_records_raw_build_output(self):
        (self.root / "bin/xcbeautify").unlink()
        result, _ = self.run_build()
        self.assert_success(result)
        self.assertIn("raw stdout\nraw stderr\n", result.stdout)
        self.assertEqual((self.output / "docbuild.log").read_text(), "raw stdout\nraw stderr\n")

    def test_formatter_failure_fails_the_build_pipeline(self):
        result, calls = self.run_build(DOCS_TEST_FORMATTER_EXIT="4")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Documentation build failed", result.stderr)
        self.assertEqual(len(calls), 1)
        self.assertTrue((self.output / "docbuild.log").exists())

    def test_custom_log_parent_is_not_created_implicitly(self):
        result, calls = self.run_build(DOC_LOG_PATH=str(self.root / "absent directory/log.txt"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call["tool"] for call in calls], ["xcodebuild"])
        self.assertFalse((self.root / "absent directory").exists())


if __name__ == "__main__":
    unittest.main()
