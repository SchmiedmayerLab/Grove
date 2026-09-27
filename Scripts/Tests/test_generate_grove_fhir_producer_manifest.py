# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import importlib.util
import json
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "generate-grove-fhir-producer-manifest.py"
SPEC = importlib.util.spec_from_file_location("generate_grove_fhir_producer_manifest", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProducerManifestTests(unittest.TestCase):
    def test_manifest_is_sorted_and_records_exact_direct_grove_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "z.json").write_text(json.dumps({
                "resourceType": "Observation",
                "meta": {"profile": [
                    "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-observation",
                    "http://hl7.org/fhir/StructureDefinition/vitalsigns",
                ]},
            }))
            (root / "a.json").write_text(json.dumps({
                "resourceType": "Bundle",
                "meta": {"profile": [
                    "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-exchange-bundle",
                ]},
            }))

            manifest = MODULE.create_manifest(
                root,
                root / "manifest.json",
                MODULE.parse_packages(["mobile=org.grovealliance.fhir.mobile"], "0.4.0"),
                "abc123",
                "0.4.0",
            )

            self.assertEqual(
                [entry["path"] for entry in manifest["resources"]],
                ["a.json", "z.json"],
            )
            self.assertEqual(manifest["schemaVersion"], 0)
            self.assertEqual(
                manifest["resources"][1]["requiredProfiles"],
                ["https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-observation"],
            )
            self.assertEqual(manifest["producer"]["revision"], "abc123")
            self.assertEqual(manifest["semanticVectors"], [])

    def test_mobile_vector_binds_to_the_named_bundle_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            resources = root / "resources"
            resources.mkdir()
            profile = "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-heart-rate"
            resource = resources / "heart-rate.json"
            resource.write_text(json.dumps({
                "resourceType": "Bundle",
                "meta": {"profile": [
                    "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-exchange-bundle",
                ]},
                "entry": [
                    {"resource": {"resourceType": "Device", "meta": {"profile": [
                        "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-application-device",
                    ]}}},
                    {"resource": {"resourceType": "Observation", "meta": {"profile": [profile]}}},
                ],
            }))
            corpus = root / "corpus.json"
            corpus.write_text(json.dumps({"vectors": [{"id": "heart-rate", "profile": profile}]}))

            manifest = MODULE.create_manifest(
                resources,
                resources / "manifest.json",
                MODULE.parse_packages(["mobile=org.grovealliance.fhir.mobile"], "0.4.0"),
                None,
                "0.4.0",
                corpus,
            )

            self.assertEqual(manifest["semanticVectors"], [{
                "id": "heart-rate",
                "path": "heart-rate.json",
                "resourcePointer": "/entry/1/resource",
            }])

    def test_mobile_vector_binding_fails_when_named_fixture_is_ambiguous(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            resources = root / "resources"
            resources.mkdir()
            profile = "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-heart-rate"
            (resources / "other.json").write_text(json.dumps({
                "resourceType": "Observation",
                "meta": {"profile": [profile]},
            }))
            corpus = root / "corpus.json"
            corpus.write_text(json.dumps({"vectors": [{"id": "heart-rate", "profile": profile}]}))

            with self.assertRaisesRegex(MODULE.ManifestError, "heart-rate.json"):
                MODULE.create_manifest(
                    resources,
                    resources / "manifest.json",
                    MODULE.parse_packages(["mobile=org.grovealliance.fhir.mobile"], "0.4.0"),
                    None,
                    "0.4.0",
                    corpus,
                )

    def test_resource_without_a_grove_profile_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            resource = root / "resource.json"
            resource.write_text(json.dumps({
                "resourceType": "Observation",
                "meta": {"profile": ["http://hl7.org/fhir/StructureDefinition/vitalsigns"]},
            }))

            with self.assertRaisesRegex(MODULE.ManifestError, "direct Grove profile"):
                MODULE.create_manifest(
                    root,
                    root / "manifest.json",
                    MODULE.parse_packages(["mobile=org.grovealliance.fhir.mobile"], "0.4.0"),
                    None,
                    "0.4.0",
                )

    def test_package_and_producer_versions_come_from_the_argument(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "a.json").write_text(json.dumps({
                "resourceType": "Observation",
                "meta": {"profile": ["https://grovealliance.org/fhir/mobile/StructureDefinition/mobile-heart-rate"]},
            }))

            manifest = MODULE.create_manifest(
                root,
                root / "manifest.json",
                MODULE.parse_packages(["mobile=org.grovealliance.fhir.mobile"], "9.9.9"),
                "abc123",
                "9.9.9",
            )

            self.assertEqual([package["version"] for package in manifest["packages"]], ["9.9.9"])
            self.assertEqual(manifest["producer"]["version"], "9.9.9")

    def test_duplicate_json_keys_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            resource = pathlib.Path(directory) / "resource.json"
            resource.write_text(
                '{"resourceType":"Observation","resourceType":"Bundle",'
                '"meta":{"profile":["https://grovealliance.org/fhir/mobile/Profile"]}}'
            )

            with self.assertRaisesRegex(MODULE.ManifestError, "duplicate JSON key"):
                MODULE.read_resource(resource)


if __name__ == "__main__":
    unittest.main()
