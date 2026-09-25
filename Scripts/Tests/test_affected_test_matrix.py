#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#

import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "affected-test-matrix.py"
SPEC = importlib.util.spec_from_file_location("affected_test_matrix", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def target(name, dependencies=None, **values):
    return {
        "name": name,
        "dependencies": [{"target": [dependency, None]} for dependency in dependencies or []],
        **values,
    }


def external_product_target(name, package):
    return {"product": [name, package, None, None]}


def package_dependency(identity, upper_bound):
    return {
        "sourceControl": [
            {
                "identity": identity,
                "location": {"remote": [{"urlString": f"https://example.com/{identity}.git"}]},
                "productFilter": None,
                "requirement": {"range": [{"lowerBound": "1.0.0", "upperBound": upper_bound}]},
            }
        ]
    }


def package_dump(targets, products=None, dependencies=None, **values):
    return {
        "name": "Grove",
        "packageKind": {"root": ["/tmp/checkout"]},
        "targets": targets,
        "products": products or [],
        "dependencies": dependencies or [],
        **values,
    }


def run_selector(*changed_paths, extra_arguments=()):
    with tempfile.NamedTemporaryFile(mode="w") as changed_file:
        changed_file.write("\n".join(changed_paths) + "\n")
        changed_file.flush()
        original_argv = sys.argv
        sys.argv = [str(SCRIPT), changed_file.name, *extra_arguments]
        output = io.StringIO()
        try:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                MODULE.main()
        finally:
            sys.argv = original_argv
    return dict(line.split("=", 1) for line in output.getvalue().splitlines())


class AffectedManifestTests(unittest.TestCase):
    def test_changed_target_includes_transitive_dependents(self):
        base = package_dump([
            target("GroveFoundation", settings=[]),
            target("Grove", ["GroveFoundation"]),
            target("GroveTests", ["Grove"]),
        ])
        head = package_dump([
            target("GroveFoundation", settings=[{"swift": "changed"}]),
            target("Grove", ["GroveFoundation"]),
            target("GroveTests", ["Grove"]),
        ])

        affected = MODULE.affected_by_manifest(base, head, MODULE.PKGS)

        self.assertEqual(affected, {"Grove", "GroveFoundation"})

    def test_new_product_and_target_are_mapped_to_their_package(self):
        base = package_dump([target("GroveHealthKitFHIR")])
        head = package_dump(
            [
                target("GroveHealthKitFHIR"),
                target("GroveHealthKitFHIRMacros", ["GroveHealthKitFHIR"]),
            ],
            products=[{"name": "GroveHealthKitFHIRMacros", "targets": ["GroveHealthKitFHIRMacros"]}],
        )

        affected = MODULE.affected_by_manifest(base, head, MODULE.PKGS)

        self.assertEqual(affected, {"GroveHealthKitFHIR"})

    def test_new_unclassified_target_fails_instead_of_silently_disappearing(self):
        base = package_dump([])
        head = package_dump([target("UnclassifiedTarget")])

        with self.assertRaisesRegex(
            MODULE.UnclassifiedTargetsError,
            "UnclassifiedTarget",
        ):
            MODULE.affected_by_manifest(base, head, MODULE.PKGS)

    def test_trait_order_is_not_a_manifest_change(self):
        base = package_dump([target("GroveChat")], traits=[
            {"name": "default", "enabledTraits": ["Textual", "MLX", "ResearchKit"]},
            {"name": "MLX", "enabledTraits": []},
        ])
        head = package_dump([target("GroveChat")], traits=[
            {"name": "MLX", "enabledTraits": []},
            {"name": "default", "enabledTraits": ["ResearchKit", "Textual", "MLX"]},
        ])

        self.assertEqual(MODULE.affected_by_manifest(base, head, MODULE.PKGS), set())

    def test_a_toggled_trait_reaches_the_targets_it_gates(self):
        gated = target("GroveChat", path="Sources/GroveChat")
        gated["dependencies"] = [{"product": ["Textual", "textual", None, {"platformNames": [], "traits": ["Textual"]}]}]
        untouched = target("GroveAccount", path="Sources/GroveAccount")
        base = package_dump([gated, untouched], traits=[{"name": "default", "enabledTraits": ["Textual"]}])
        head = package_dump([gated, untouched], traits=[{"name": "default", "enabledTraits": []}])

        self.assertEqual(MODULE.affected_by_manifest(base, head, MODULE.PKGS), {"GroveChat"})

    def test_global_manifest_change_falls_back_to_every_package(self):
        base = package_dump([], platforms=[{"platformName": "ios", "version": "15.0"}])
        head = package_dump([], platforms=[{"platformName": "ios", "version": "18.0"}])

        self.assertIsNone(MODULE.affected_by_manifest(base, head, MODULE.PKGS))

    def test_external_dependency_change_follows_target_dependents(self):
        macro = target("GroveAccountMacros")
        macro["dependencies"] = [external_product_target("SwiftSyntaxMacros", "swift-syntax")]
        targets = [
            macro,
            target("GroveAccount", ["GroveAccountMacros"]),
            target("GroveAccountTests", ["GroveAccount"]),
        ]
        base = package_dump(targets, dependencies=[package_dependency("swift-syntax", "2.0.0")])
        head = package_dump(targets, dependencies=[package_dependency("swift-syntax", "3.0.0")])

        affected = MODULE.affected_by_manifest(base, head, MODULE.PKGS)

        self.assertEqual(affected, {"GroveAccount"})


class FHIRConformanceSelectionTests(unittest.TestCase):
    def test_validator_script_runs_only_fhir_packages_and_conformance(self):
        result = run_selector("Scripts/validate-fhir-conformance.sh")

        self.assertEqual(result["has_fhir_conformance"], "true")
        self.assertEqual(set(result["affected"].split(",")), MODULE.FHIR_PACKAGES)


class InfrastructureSelectionTests(unittest.TestCase):
    def test_source_directory_outside_every_package_runs_full_matrix(self):
        with contextlib.redirect_stderr(io.StringIO()):
            result = run_selector("Sources/NotAPackage/File.swift")

        self.assertEqual(result["has_jobs"], "true")
        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["has_fhir_conformance"], "true")

    def test_documentation_content_does_not_run_package_tests(self):
        result = run_selector("Sources/Grove/Grove.docc/GettingStarted.md")

        self.assertEqual(result["has_jobs"], "false")
        self.assertEqual(result["has_ui_jobs"], "false")
        self.assertEqual(result["affected"], "(none)")

    def test_classified_non_test_script_does_not_run_package_tests(self):
        result = run_selector("Scripts/build-documentation.sh")

        self.assertEqual(result["has_jobs"], "false")
        self.assertEqual(result["affected"], "(none)")

    def test_unknown_script_must_be_classified(self):
        with self.assertRaises(SystemExit):
            run_selector("Scripts/new-build-tool.sh")

    def test_shared_all_platform_test_plan_runs_every_package(self):
        result = run_selector("Tests/TestPlans/_All-iOS.xctestplan")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["has_fhir_conformance"], "false")


class UITestProjectsSelectionTests(unittest.TestCase):
    """The UI-test project manifest is diffed per table, so a targeted change stays targeted."""

    HEAD = pathlib.Path(MODULE.ROOT) / MODULE.UI_TEST_PROJECTS_PATH

    def run_with_base(self, base_content):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".toml") as base_file:
            base_file.write(base_content)
            base_file.flush()
            return run_selector(
                MODULE.UI_TEST_PROJECTS_PATH,
                extra_arguments=("--base-ui-test-projects", base_file.name),
            )

    def test_without_a_base_version_stays_conservative(self):
        result = run_selector(MODULE.UI_TEST_PROJECTS_PATH)

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))

    def test_a_changed_table_affects_only_its_package(self):
        base = self.HEAD.read_text().replace("[GroveLLM]", "[GroveLLM]\nremoved_marker = true", 1)
        self.assertNotEqual(base, self.HEAD.read_text())

        result = self.run_with_base(base)

        self.assertEqual(result["affected"], "GroveLLM")

    def test_an_untouched_manifest_affects_nothing(self):
        result = self.run_with_base(self.HEAD.read_text())

        self.assertEqual(result["affected"], "(none)")

    def test_an_unclassified_table_stays_conservative(self):
        base = self.HEAD.read_text() + '\n[NotAPackage]\napp_products = ["Grove"]\n'

        result = self.run_with_base(base)

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))


class SourceChangeSelectionTests(unittest.TestCase):
    """A source change schedules its package and everything that builds on it."""

    def run_with_head(self, *changed_paths, head):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as head_file:
            head_file.write(json.dumps(head))
            head_file.flush()
            return run_selector(*changed_paths, extra_arguments=("--head-package-dump", head_file.name))

    def test_a_changed_target_schedules_its_consumers(self):
        head = package_dump([
            target("GroveFoundation", path="Sources/GroveFoundation"),
            target("GroveChat", ["GroveFoundation"], path="Sources/GroveChat"),
            target("GroveLLM", ["GroveChat"], path="Sources/GroveLLM"),
            target("GroveAccount", ["GroveFoundation"], path="Sources/GroveAccount"),
        ])
        result = self.run_with_head("Sources/GroveChat/ChatView.swift", head=head)

        self.assertEqual(set(result["affected"].split(",")), {"GroveChat", "GroveLLM"})

    def test_a_shared_module_without_a_package_schedules_its_consumers(self):
        head = package_dump([
            target("GroveLegacyIdentifiers", path="Sources/GroveLegacyIdentifiers"),
            target("GroveFoundation", ["GroveLegacyIdentifiers"], path="Sources/GroveFoundation"),
            target("GroveChat", ["GroveFoundation"], path="Sources/GroveChat"),
        ])
        result = self.run_with_head("Sources/GroveLegacyIdentifiers/Identifiers.swift", head=head)

        self.assertEqual(set(result["affected"].split(",")), {"GroveFoundation", "GroveChat"})

    def test_a_test_change_schedules_its_package(self):
        head = package_dump([
            target("GroveAccount", path="Sources/GroveAccount"),
            target("GroveAccountTests", ["GroveAccount"], path="Tests/GroveAccountTests"),
            target("GroveChat", path="Sources/GroveChat"),
        ])
        result = self.run_with_head("Tests/GroveAccountTests/AccountTests.swift", head=head)

        self.assertEqual(result["affected"], "GroveAccount")

    def test_without_the_head_graph_only_the_owner_is_scheduled(self):
        result = run_selector("Sources/GroveChat/ChatView.swift")

        self.assertEqual(result["affected"], "GroveChat")


class FullSuiteSelectionTests(unittest.TestCase):
    def test_manifest_and_shared_ci_changes_run_the_full_suite(self):
        expected = run_selector("__ALL__")
        paths = (
            "Package.swift",
            "Package@swift-6.1.swift",
            ".github/workflows/tests.yml",
            ".github/workflows/static-analysis.yml",
            ".github/workflows/release.yaml",
            ".github/actions/setup/action.yml",
            ".github/actions/setup/setup.sh",
            ".swiftpm/xcode/xcshareddata/xcschemes/Grove.xcscheme",
            "Scripts/run-package-tests.sh",
        )
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(run_selector(path), expected)

    def run_with_graphs(self, *paths, base, head):
        with (
            tempfile.NamedTemporaryFile(mode="w", suffix=".json") as base_file,
            tempfile.NamedTemporaryFile(mode="w", suffix=".json") as head_file,
        ):
            base_file.write(json.dumps(base))
            base_file.flush()
            head_file.write(json.dumps(head))
            head_file.flush()
            return run_selector(
                *paths,
                extra_arguments=("--base-package-dump", base_file.name, "--head-package-dump", head_file.name),
            )

    def test_classifiable_manifest_change_still_runs_the_full_suite(self):
        base = package_dump([target("GroveChat", settings=[])])
        head = package_dump([target("GroveChat", settings=[{"swift": "changed"}])])
        expected = run_selector("__ALL__")

        for path in ("Package.swift", "Package@swift-6.1.swift"):
            with self.subTest(path=path):
                self.assertEqual(self.run_with_graphs(path, base=base, head=head), expected)

    def test_identical_evaluated_manifests_still_run_the_full_suite(self):
        manifest = package_dump([target("GroveChat")])

        self.assertEqual(
            self.run_with_graphs("Package.swift", base=manifest, head=manifest), run_selector("__ALL__"),
        )

    def test_shared_ci_changes_override_source_dependency_selection(self):
        manifest = package_dump([
            target("GroveChat", path="Sources/GroveChat"),
            target("GroveLLM", ["GroveChat"], path="Sources/GroveLLM"),
        ])
        result = self.run_with_graphs(
            "Sources/GroveChat/ChatView.swift", ".github/workflows/tests.yml", base=manifest, head=manifest,
        )

        self.assertEqual(result, run_selector("__ALL__"))

    def test_full_manifest_run_rejects_new_unclassified_targets(self):
        base = package_dump([])
        head = package_dump([target("UnclassifiedTarget")])

        with self.assertRaisesRegex(SystemExit, "UnclassifiedTarget"):
            self.run_with_graphs("Package.swift", base=base, head=head)


class PackageConfigurationSelectionTests(unittest.TestCase):
    def test_package_configuration_changes_remain_package_specific(self):
        head = pathlib.Path(MODULE.ROOT, "packages.toml").read_text()
        base = head.replace("[GroveLLM]", "[GroveLLM]\nremoved_marker = true", 1)
        self.assertNotEqual(base, head)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".toml") as base_file:
            base_file.write(base)
            base_file.flush()
            result = run_selector(
                "packages.toml",
                extra_arguments=("--base-packages", base_file.name),
            )

        self.assertEqual(result["affected"], "GroveLLM")


class RunnerRoutingTests(unittest.TestCase):
    def test_self_hosted_unit_and_ui_jobs_do_not_require_stanford(self):
        result = run_selector("__ALL__")
        for matrix in ("matrix", "ui_matrix"):
            with self.subTest(matrix=matrix):
                jobs = [job for job in json.loads(result[matrix])["include"] if job["selfHosted"]]
                self.assertTrue(jobs, "The routing assertion must cover emitted self-hosted jobs")
                for job in jobs:
                    with self.subTest(package=job["package"], platform=job["platform"]):
                        labels = json.loads(job["selfHostedLabels"])
                        self.assertTrue({"self-hosted", "macOS"}.issubset(labels))
                        self.assertNotIn("stanford", labels)

    def test_runtime_assertions_keeps_its_python_runner_requirement(self):
        result = run_selector("Sources/RuntimeAssertions/Assertions.swift")
        jobs = json.loads(result["matrix"])["include"]

        self.assertTrue(jobs)
        for job in jobs:
            self.assertEqual(job["package"], "RuntimeAssertions")
            self.assertTrue(job["selfHosted"])
            self.assertIn("python3.11+", json.loads(job["selfHostedLabels"]))

    def test_linux_and_ordinary_unit_jobs_remain_github_hosted(self):
        result = run_selector("__ALL__")
        jobs = json.loads(result["matrix"])["include"]
        linux_jobs = [job for job in jobs if job["platform"] == "Linux"]
        account_jobs = [job for job in jobs if job["package"] == "GroveAccount"]

        self.assertTrue(linux_jobs)
        self.assertTrue(account_jobs)
        self.assertTrue(all(not job["selfHosted"] for job in linux_jobs + account_jobs))


if __name__ == "__main__":
    unittest.main()
