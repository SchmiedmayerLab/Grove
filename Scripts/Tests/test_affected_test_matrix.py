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


def run_selector(*changed_paths):
    with tempfile.NamedTemporaryFile(mode="w") as changed_file:
        changed_file.write("\n".join(changed_paths) + "\n")
        changed_file.flush()
        original_argv = sys.argv
        sys.argv = [str(SCRIPT), changed_file.name]
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

    def test_unrelated_script_runs_full_matrix_without_conformance(self):
        result = run_selector("Scripts/run-package-tests.sh")

        self.assertEqual(result["has_fhir_conformance"], "false")
        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))


class InfrastructureSelectionTests(unittest.TestCase):
    def test_documentation_content_does_not_run_package_tests(self):
        result = run_selector("Sources/Grove/Grove.docc/GettingStarted.md")

        self.assertEqual(result["has_jobs"], "false")
        self.assertEqual(result["has_ui_jobs"], "false")
        self.assertEqual(result["affected"], "(none)")

    def test_classified_non_test_script_does_not_run_package_tests(self):
        result = run_selector("Scripts/build-documentation.sh")

        self.assertEqual(result["has_jobs"], "false")
        self.assertEqual(result["affected"], "(none)")

    def test_tests_workflow_runs_every_package(self):
        result = run_selector(".github/workflows/tests.yml")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["has_fhir_conformance"], "true")

    def test_shared_local_action_runs_every_package(self):
        result = run_selector(".github/actions/setup/action.yml")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))

    def test_unknown_script_stays_conservative(self):
        result = run_selector("Scripts/new-build-tool.sh")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))

    def test_shared_all_platform_test_plan_runs_every_package(self):
        result = run_selector("Tests/TestPlans/_All-iOS.xctestplan")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["has_fhir_conformance"], "false")


if __name__ == "__main__":
    unittest.main()
