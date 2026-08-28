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
            "canonical": "https://example.org/sensor",
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
        discriminator = "native-recording"
        adapter = pathlib.Path(directory) / "sensorkit-adapter.json"
        adapter.write_text(json.dumps({
            "schemaVersion": 1,
            "version": "0.6.0",
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
                "contract": "catalog/exchange-protocol.json",
                "protocolVersion": 2,
                "adapterId": "sensorkit",
                "sourceRecord": {
                    "identityKind": "source-record",
                    "identifierRole": "source-record",
                    "components": [
                        "adapter-id",
                        "source-type",
                        "repository-scope-system",
                        "repository-scope-value",
                        "native-record-id",
                    ],
                },
                "sourceOutput": {
                    "identityKind": "source-output",
                    "identifierRole": "source-output",
                    "components": [
                        "adapter-id",
                        "source-type",
                        "repository-scope-system",
                        "repository-scope-value",
                        "native-record-id",
                        "output-role",
                        "output-discriminator",
                    ],
                },
                "sourceArtifact": {
                    "identityKind": "source-artifact",
                    "identifierRole": "source-artifact",
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
                "raw": {"status": "mapped-standard", "formats": ["grove-csv-1"]},
            }],
        }))
        registry = pathlib.Path(directory) / "format-registry.json"
        registry.write_text(json.dumps({
            "schemaVersion": 1,
            "fhirVersion": "4.0.1",
            "version": "0.6.0",
            "formats": {
                "grove-csv-1": {"title": "Grove CSV 1", "contentType": "text/csv", "status": "active"},
                "native-json-1": {"title": "Native JSON 1", "contentType": "application/json", "status": "active"},
            },
        }))
        return sensor, adapter, registry

    def test_generates_assertions_constants_and_exact_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter, registry = self.write_catalogs(directory)
            generated = MODULE.generate(sensor, adapter, registry)

            self.assertLess(
                generated.index("case callerAuthorizedOpaquePayload"),
                generated.index("case verifiedSanitizedInput"),
            )
            self.assertIn("sourceToken: \"SRSensor.accelerometer\"", generated)
            self.assertIn("status: .mappedStandard", generated)
            self.assertIn("sensorConversionProvenanceProfile", generated)
            self.assertIn("rawFormats: [.groveCSV1]", generated)
            # The registry is projected as a closed type, so an unlisted format cannot be named.
            self.assertIn('case groveCSV1 = "grove-csv-1"', generated)
            self.assertIn(
                "public enum RegisteredRecordingFormat: String, CaseIterable, Hashable, Sendable {",
                generated,
            )
            self.assertIn(
                "recordingFormatCodeSystem = "
                "\"https://example.org/sensor/CodeSystem/grove-recording-format\"",
                generated,
            )
            self.assertNotIn("sourceRecordIdentifierSystem", generated)
            self.assertNotIn("outputIdentifierSystem", generated)
            self.assertNotIn("Codable", generated.split("public enum", 1)[1].split("{", 1)[0])

    def test_rejects_adapter_specific_legacy_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter, registry = self.write_catalogs(directory)
            value = json.loads(adapter.read_text())
            value["identity"] = {
                "sourceRecord": {"system": "https://example.org/source"},
                "output": {"separator": "|", "versionPrefix": "v1", "vectors": []},
            }
            adapter.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "exchange-protocol.json"):
                MODULE.generate(sensor, adapter, registry)

    def test_rejects_admitted_raw_row_without_registry_formats(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [{
                "sourceToken": "SRSensor.accelerometer",
                "sourceTypeCode": "accelerometer",
                "minimumIOS": "14.0",
                "scope": "grove-implemented",
                "status": "mapped-standard",
                "structured": {"status": "deferred", "reason": "not lossless"},
                "raw": {"status": "mapped-standard"},
            }]
            sensor, adapter, registry = self.write_catalogs(directory, entries=rows)
            with self.assertRaisesRegex(ValueError, "must declare registry formats"):
                MODULE.generate(sensor, adapter, registry)

    def test_rejects_duplicate_assertions(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter, registry = self.write_catalogs(
                directory,
                ["verified-sanitized-input", "verified-sanitized-input"],
            )
            with self.assertRaisesRegex(ValueError, "must be unique"):
                MODULE.generate(sensor, adapter, registry)

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
            sensor, adapter, registry = self.write_catalogs(directory, entries=rows)
            with self.assertRaisesRegex(ValueError, "must be sorted"):
                MODULE.generate(sensor, adapter, registry)

    def test_rejects_non_r4_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor, adapter, registry = self.write_catalogs(directory)
            value = json.loads(sensor.read_text())
            value["fhirVersion"] = "4.3.0"
            sensor.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "not an R4"):
                MODULE.generate(sensor, adapter, registry)


if __name__ == "__main__":
    unittest.main()
