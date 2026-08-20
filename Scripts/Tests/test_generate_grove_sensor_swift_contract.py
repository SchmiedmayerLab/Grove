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
import uuid


SCRIPT = pathlib.Path(__file__).parents[1] / "generate-grove-sensor-swift-contract.py"
SPEC = importlib.util.spec_from_file_location("generate_grove_sensor_swift_contract", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SensorSwiftContractTests(unittest.TestCase):
    @staticmethod
    def write_catalogs(directory, assertions=None, entries=None):
        assertions = assertions or [
            "caller-authorized-opaque-payload",
            "verified-sanitized-input",
        ]
        sensor = pathlib.Path(directory) / "sensor-catalog.json"
        sensor.write_text(json.dumps({
            "fhirVersion": "4.0.1",
            "contracts": [
                {
                    "id": "recording-document",
                    "profile": "https://example.org/sensor/recording",
                    "payloadAdmission": {"allowedAssertions": assertions},
                },
                {
                    "id": "conversion-provenance",
                    "profile": "https://example.org/sensor/provenance",
                },
            ],
        }))
        source_system = "https://example.org/sensorkit/source"
        namespace = uuid.UUID("c0b8814a-8178-5e92-996a-c4cf36cd640b")
        discriminator = "native-recording"
        preimage = json.dumps(
            [source_system, "879d9ea2-21cb-4527-b59b-2831dc4c84ab", discriminator],
            separators=(",", ":"),
        )
        adapter = pathlib.Path(directory) / "sensorkit-adapter.json"
        adapter.write_text(json.dumps({
            "schemaVersion": 1,
            "version": "0.2.0",
            "fhirVersion": "4.0.1",
            "packageId": "org.grovealliance.fhir.sensorkit",
            "canonical": "https://example.org/sensorkit",
            "statusVocabulary": [
                "supported", "mapped-standard", "provider-specific", "deferred",
                "intentionally-unsupported",
            ],
            "rawPayloadAdmission": {"allowedAssertions": assertions},
            "profileClaims": {
                "sharedObservation": {"adapterProfile": "https://example.org/sensorkit/observation"},
                "hybridObservation": {"adapterProfile": "https://example.org/sensorkit/ecg"},
                "recordingDocument": {
                    "sourceNeutralProfile": "https://example.org/sensor/recording",
                    "adapterProfile": "https://example.org/sensorkit/recording",
                    "defaultOutputDiscriminator": discriminator,
                },
                "conversionProvenance": {"profile": "https://example.org/sensorkit/provenance"},
            },
            "identity": {
                "sourceRecord": {"system": source_system},
                "output": {
                    "system": "https://example.org/sensorkit/output",
                    "namespace": str(namespace),
                    "vectors": [{
                        "outputDiscriminator": discriminator,
                        "canonicalPreimage": preimage,
                        "identifierValue": str(uuid.uuid5(namespace, preimage)),
                    }],
                },
            },
            "entries": entries or [{
                "sourceToken": "SRSensor.accelerometer",
                "sourceTypeCode": "accelerometer",
                "groveSensor": "Sensor.accelerometer",
                "minimumIOS": "14.0",
                "scope": "grove-implemented",
                "status": "mapped-standard",
                "structured": {"status": "deferred", "reason": "not lossless"},
                "raw": {"status": "mapped-standard"},
            }],
        }))
        return sensor, adapter

    def test_generates_assertions_constants_and_exact_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter = self.write_catalogs(directory)
            generated = MODULE.generate(sensor, adapter)

            self.assertLess(
                generated.index("case callerAuthorizedOpaquePayload"),
                generated.index("case verifiedSanitizedInput"),
            )
            self.assertIn("sourceToken: \"SRSensor.accelerometer\"", generated)
            self.assertIn("status: .mappedStandard", generated)
            self.assertIn("sensorConversionProvenanceProfile", generated)
            self.assertNotIn("Codable", generated.split("public enum", 1)[1].split("{", 1)[0])

    def test_rejects_duplicate_assertions(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter = self.write_catalogs(
                directory,
                ["verified-sanitized-input", "verified-sanitized-input"],
            )
            with self.assertRaisesRegex(ValueError, "must be unique"):
                MODULE.generate(sensor, adapter)

    def test_rejects_unsorted_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [
                {
                    "sourceToken": token,
                    "sourceTypeCode": token[-1].lower(),
                    "minimumIOS": "14.0",
                    "scope": "grove-implemented",
                    "status": "deferred",
                    "reason": "test",
                }
                for token in ["SRSensor.z", "SRSensor.a"]
            ]
            sensor, adapter = self.write_catalogs(directory, entries=rows)
            with self.assertRaisesRegex(ValueError, "must be sorted"):
                MODULE.generate(sensor, adapter)

    def test_rejects_non_r4_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter = self.write_catalogs(directory)
            value = json.loads(sensor.read_text())
            value["fhirVersion"] = "4.3.0"
            sensor.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "not an R4"):
                MODULE.generate(sensor, adapter)


if __name__ == "__main__":
    unittest.main()
