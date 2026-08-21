#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "generate-grove-fhir-swift-contract.py"
SPEC = importlib.util.spec_from_file_location("generate_grove_fhir_swift_contract", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GenerateGroveFHIRSwiftContractTests(unittest.TestCase):
    def catalogs(self) -> dict[str, dict]:
        base = {"fhirVersion": "4.0.1", "version": "0.2.0"}
        return {
            "package-graph.json": {
                **base,
                "canonicalRoot": "https://grovealliance.org/fhir",
                "packages": [
                    {
                        "source": "mobile",
                        "canonical": "https://grovealliance.org/fhir/mobile",
                        "profiles": ["grove-mobile-exchange-bundle"],
                    },
                    {
                        "source": "healthkit",
                        "canonical": "https://grovealliance.org/fhir/healthkit",
                        "profiles": ["healthkit-conversion-provenance", "healthkit-ecg-observation"],
                    },
                ],
            },
            "measurement-catalog.json": {
                **base,
                "statusVocabulary": ["supported", "deferred"],
                "measurements": [],
            },
            "profile-claims.json": {
                **base,
                "observationAdapterClaim": {
                    "cardinality": 2,
                    "inheritedProfilesAreNotDeclared": True,
                    "adapterProfiles": [
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-ecg-observation"
                    ],
                    "sharedSensorProfiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/grove-sensor-ecg-observation"
                    ],
                    "forbiddenExplicitProfiles": [],
                },
            },
            "healthkit-adapter.json": {
                **base,
                "sourceTypeCoding": {
                    "system": "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-source-type"
                },
                "conversionProvenanceProfile": (
                    "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                    "healthkit-conversion-provenance"
                ),
                "producerCanonicalization": {
                    "effectivePrecision": "millisecond",
                    "effectiveRounding": "half-even",
                    "scalarQuantityDecimal": "shortest-round-trip",
                    "sensorAndEcgTiming": "excluded",
                },
                "sensorAdapterClaims": {
                    "electrocardiogram": {
                        "sourceTypeIdentifier": "HKDataTypeIdentifierElectrocardiogram",
                        "profiles": [
                            "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                            "grove-sensor-ecg-observation",
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-ecg-observation",
                        ],
                        "correlatedSymptomEvidence": {
                            "url": "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-ecg-correlated-symptom"
                        },
                    }
                },
                "rows": [
                    {
                        "sourceTypeIdentifier": "HKDataTypeIdentifierElectrocardiogram",
                        "title": "ECG",
                        "status": "supported",
                        "measurementIDs": ["electrocardiogram"],
                        "profiles": [
                            "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                            "grove-sensor-ecg-observation",
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-ecg-observation",
                        ],
                        "requirement": "Caller supplies complete evidence.",
                    },
                    {
                        "sourceTypeIdentifier": "HKQuantityTypeIdentifierBodyMassIndex",
                        "title": "BMI",
                        "status": "supported",
                        "measurementIDs": ["body-mass-index"],
                        "profiles": [
                            "http://hl7.org/fhir/StructureDefinition/bmi",
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-observation",
                        ],
                        "requirement": None,
                    },
                ],
            },
            "exchange-identity.json": {
                "profile": (
                    "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                    "grove-mobile-exchange-bundle"
                ),
                "entryIdentifierExtension": (
                    "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                    "grove-exchange-entry-identifier"
                ),
                "fullUrlAlgorithm": {"name": "uuid-v5-jcs-identifier-v1", "namespace": "test"},
            },
        }

    def generate(self, catalogs: dict[str, dict]) -> str:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in catalogs.items():
                (root / name).write_text(json.dumps(value), encoding="utf-8")
            return MODULE.generate(root)

    def test_generates_exact_healthkit_inventory_and_adapter_contract(self):
        generated = self.generate(self.catalogs())

        self.assertIn("public enum GroveFHIRHealthKitCatalog", generated)
        self.assertIn("HKDataTypeIdentifierElectrocardiogram", generated)
        self.assertIn("HKQuantityTypeIdentifierBodyMassIndex", generated)
        self.assertIn("public static let bodyMassIndexProfiles", generated)
        self.assertIn("public static let electrocardiogramProfiles", generated)
        self.assertIn("public static let mobileEffectiveRounding = \"half-even\"", generated)

    def test_rejects_unsorted_healthkit_inventory(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["rows"].reverse()

        with self.assertRaisesRegex(ValueError, "must be sorted"):
            self.generate(catalogs)

    def test_rejects_ambiguous_multi_measurement_healthkit_row(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["rows"][0]["measurementIDs"] = ["one", "two"]

        with self.assertRaisesRegex(ValueError, "at most one measurement"):
            self.generate(catalogs)


if __name__ == "__main__":
    unittest.main()
