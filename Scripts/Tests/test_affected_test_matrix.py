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
                target("GroveFHIRContract"),
            ],
            products=[{"name": "GroveFHIRContract", "targets": ["GroveFHIRContract"]}],
        )

        affected = MODULE.affected_by_manifest(base, head, MODULE.PKGS)

        self.assertEqual(affected, {"GroveFHIR"})

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
        self.assertEqual(
            set(result["fhir_components"].split(",")),
            MODULE.ALL_FHIR_COMPONENTS,
        )
        self.assertEqual(
            set(result["affected"].split(",")),
            MODULE.FHIR_PACKAGES & set(MODULE.PKGS),
        )

    def test_producer_manifest_generator_runs_fhir_conformance(self):
        result = run_selector("Scripts/generate-grove-fhir-producer-manifest.py")

        self.assertEqual(result["has_fhir_conformance"], "true")
        self.assertEqual(
            set(result["fhir_components"].split(",")),
            MODULE.ALL_FHIR_COMPONENTS,
        )
        self.assertEqual(
            set(result["affected"].split(",")),
            MODULE.FHIR_PACKAGES & set(MODULE.PKGS),
        )

    def test_unrelated_script_runs_full_matrix_without_conformance(self):
        result = run_selector("Scripts/run-package-tests.sh")

        self.assertEqual(result["has_fhir_conformance"], "false")
        self.assertEqual(result["fhir_components"], "(none)")
        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))

    def test_healthkit_development_scope_suppresses_manifest_fanout_and_ui(self):
        result = run_selector(
            "Package.swift",
            ".github/workflows/tests.yml",
            extra_arguments=("--development-scope", "healthkit"),
        )

        self.assertEqual(result["affected"], "GroveHealthKitFHIR")
        self.assertEqual(result["has_fhir_conformance"], "true")
        self.assertEqual(result["fhir_components"], "healthkit")
        self.assertEqual(result["has_ui_jobs"], "false")

    def test_development_scope_cannot_masquerade_as_full_readiness(self):
        with self.assertRaisesRegex(SystemExit, "cannot be combined"):
            run_selector(
                "Sources/GroveHealthKitFHIR/HealthKitFHIRConverter.swift",
                extra_arguments=("--development-scope", "healthkit", "--full-readiness"),
            )

    def test_healthkit_ready_pr_runs_full_matrix_with_only_applicable_ig(self):
        result = run_selector(
            "Sources/GroveHealthKitFHIR/HealthKitFHIRConverter.swift",
            ".github/workflows/tests.yml",
            extra_arguments=("--full-readiness",),
        )

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["fhir_components"], "healthkit")
        self.assertEqual(result["has_fhir_conformance"], "true")
        self.assertEqual(result["has_ui_jobs"], "true")
        unit_jobs = {
            (job["package"], job["platform"])
            for job in json.loads(result["matrix"])["include"]
        }
        ui_jobs = {
            (job["package"], job["platform"])
            for job in json.loads(result["ui_matrix"])["include"]
        }
        self.assertIn(("Grove", "macCatalyst"), unit_jobs)
        self.assertIn(("Grove", "visionOS"), unit_jobs)
        self.assertIn(("GroveViews", "iPadOS"), ui_jobs)

    def test_questionnaire_ready_pr_runs_only_questionnaire_ig(self):
        result = run_selector(
            "Sources/GroveQuestionnaire/Model/Questionnaire.swift",
            "Scripts/validate-fhir-conformance.sh",
            extra_arguments=("--full-readiness",),
        )

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["fhir_components"], "questionnaire")
        self.assertEqual(result["has_fhir_conformance"], "true")

    def test_sensor_ready_pr_runs_only_sensor_ig(self):
        result = run_selector(
            "Sources/GroveSensorKit/SensorKit.swift",
            "Scripts/validate-fhir-conformance.sh",
            extra_arguments=("--full-readiness",),
        )

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(result["fhir_components"], "sensor")
        self.assertEqual(result["has_fhir_conformance"], "true")

    def test_explicit_all_selects_every_implementation_conformance_lane(self):
        result = run_selector("__ALL__")

        self.assertEqual(set(result["affected"].split(",")), set(MODULE.PKGS))
        self.assertEqual(
            set(result["fhir_components"].split(",")),
            MODULE.ALL_FHIR_COMPONENTS,
        )

    def test_sensor_development_scope_runs_only_source_and_fhir_packages(self):
        result = run_selector(
            "Package.swift",
            ".github/workflows/tests.yml",
            extra_arguments=("--development-scope", "sensor"),
        )

        self.assertEqual(set(result["affected"].split(",")), {"GroveSensorKit", "GroveSensorKitFHIR"})
        self.assertEqual(result["has_fhir_conformance"], "true")
        self.assertEqual(result["has_ui_jobs"], "false")


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
        self.assertEqual(
            set(result["fhir_components"].split(",")),
            MODULE.ALL_FHIR_COMPONENTS,
        )

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
