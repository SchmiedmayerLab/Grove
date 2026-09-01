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
        base = {"fhirVersion": "4.0.1", "version": "0.6.0"}
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
                        "profiles": [
                            "healthkit-application-device",
                            "healthkit-conversion-provenance",
                            "healthkit-ecg-observation",
                        ],
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
                "healthKitSingleProfileObservationClaims": {
                    "profiles": [],
                },
                "healthConnectPlatformExclusiveClaims": {
                    "profiles": [],
                },
                "sensorKitPlatformExclusiveClaims": {
                    "profiles": [],
                },
                "sensorKitHybridObservationClaims": {
                    "profiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                        "grove-sensor-ecg-observation",
                        "https://grovealliance.org/fhir/sensorkit/StructureDefinition/"
                        "sensorkit-ecg-observation",
                    ],
                },
                "healthConnectSpecimenClaim": {
                    "resourceType": "Specimen",
                    "cardinality": 1,
                    "profile": (
                        "https://grovealliance.org/fhir/health-connect/StructureDefinition/"
                        "health-connect-specimen"
                    ),
                    "otherProfilesAllowed": False,
                },
                "healthKitPlatformExclusiveResourceClaims": [
                    {
                        "resourceType": "MedicationAdministration",
                        "cardinality": 1,
                        "profile": (
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-medication-dose-event"
                        ),
                        "otherProfilesAllowed": False,
                    },
                    {
                        "resourceType": "MedicationStatement",
                        "cardinality": 1,
                        "profile": (
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-user-annotated-medication"
                        ),
                        "otherProfilesAllowed": False,
                    },
                    {
                        "resourceType": "VisionPrescription",
                        "cardinality": 1,
                        "profile": (
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-vision-prescription"
                        ),
                        "otherProfilesAllowed": False,
                    },
                ],
                "sensorRecordingDocumentClaim": {
                    "cardinality": 1,
                    "profiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                        "grove-sensor-recording-document"
                    ],
                    "otherProfilesAllowed": False,
                    "requiredIdentifierRoles": ["source-record", "source-output", "source-artifact"],
                },
                "healthKitRecordingDocumentClaim": {
                    "cardinality": 2,
                    "profiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                        "grove-sensor-recording-document",
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                        "healthkit-recording-document",
                    ],
                    "otherProfilesAllowed": False,
                    "requiredIdentifierRoles": ["source-record", "source-output", "source-artifact"],
                },
                "healthKitClinicalRecordDocumentClaim": {
                    "cardinality": 1,
                    "profiles": [
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                        "healthkit-clinical-record-document"
                    ],
                    "otherProfilesAllowed": False,
                    "requiredIdentifierRoles": ["source-record", "source-output", "source-artifact"],
                },
                "sensorKitRecordingDocumentClaim": {
                    "cardinality": 2,
                    "profiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                        "grove-sensor-recording-document",
                        "https://grovealliance.org/fhir/sensorkit/StructureDefinition/"
                        "sensorkit-recording-document",
                    ],
                    "otherProfilesAllowed": False,
                    "requiredIdentifierRoles": ["source-record", "source-output", "source-artifact"],
                },
                "providerRecordingDocumentClaim": {
                    "cardinality": 2,
                    "profiles": [
                        "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                        "grove-sensor-recording-document",
                        "https://grovealliance.org/fhir/providers/StructureDefinition/"
                        "providers-recording-document",
                    ],
                    "otherProfilesAllowed": False,
                    "requiredIdentifierRoles": ["source-record", "source-output", "source-artifact"],
                },
                "activeDeviceClaims": [
                    {
                        "id": "mobile-application-device",
                        "cardinality": 1,
                        "profiles": [
                            "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                            "grove-application-device"
                        ],
                        "otherProfilesAllowed": False,
                        "requiredIdentifierRoles": ["device-snapshot"],
                    }
                ],
                "activeQuestionnaireResponseClaim": {
                    "cardinality": 1,
                    "profiles": [
                        "https://grovealliance.org/fhir/questionnaire/StructureDefinition/"
                        "grove-questionnaire-response"
                    ],
                    "otherProfilesAllowed": False,
                },
                "adapterConversionProvenanceClaims": [
                    {
                        "adapter": "healthkit",
                        "profile": (
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-conversion-provenance"
                        ),
                        "targetAdapterProfiles": [
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-ecg-observation"
                        ],
                    }
                ],
            },
            "healthkit-adapter.json": {
                **base,
                "sourceTypeExtension": {
                    "url": (
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                        "healthkit-source-type"
                    ),
                    "valueSystem": "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-source-type",
                    "valueElement": "valueCode",
                    "cardinality": "exactly one",
                    "contexts": [
                        "Observation",
                        "DocumentReference",
                        "VisionPrescription",
                        "MedicationAdministration",
                        "MedicationStatement",
                    ],
                    "rule": "lineage",
                },
                "conversionProvenanceProfile": (
                    "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                    "healthkit-conversion-provenance"
                ),
                "applicationDeviceIdentity": {
                    "profile": (
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                        "healthkit-application-device"
                    ),
                    "snapshotIdentifierRole": "device-snapshot",
                    "bundleIdentifier": {
                        "system": (
                            "https://grovealliance.org/fhir/healthkit/NamingSystem/"
                            "apple-bundle-id"
                        ),
                        "typeSystem": (
                            "https://grovealliance.org/fhir/healthkit/CodeSystem/"
                            "healthkit-identifier-type"
                        ),
                        "typeCode": "apple-bundle-id",
                        "cardinality": "1..1",
                    },
                },
                "clinicalRecordAdmission": {
                    "profile": (
                        "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                        "healthkit-clinical-record-document"
                    ),
                    "payloadFormat": "fhir-resource",
                    "sourceFHIRReleaseField": "HKFHIRVersion.fhirRelease",
                    "admittedFHIRReleases": ["dstu2", "r4"],
                    "fhirRepresentation": {
                        "resourceType": "DocumentReference",
                        "contentTypeByRelease": {
                            "dstu2": "application/fhir+json; fhirVersion=1.0",
                            "r4": "application/fhir+json; fhirVersion=4.0",
                        },
                    },
                    "rejectedFHIRReleases": ["unknown"],
                    "rule": "DSTU2 or R4, byte-preserved.",
                },
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
            "providers-adapter.json": {
                **base,
                "providers": [
                    {
                        "id": "google-health-api",
                        "measurementOwner": "google-health",
                        "observationProfile": (
                            "https://grovealliance.org/fhir/google-health/StructureDefinition/"
                            "google-health-observation"
                        ),
                    },
                    {
                        "id": "oura",
                        "measurementOwner": "oura",
                        "observationProfile": (
                            "https://grovealliance.org/fhir/oura/StructureDefinition/"
                            "oura-observation"
                        ),
                    },
                    {
                        "id": "withings",
                        "measurementOwner": "withings",
                        "observationProfile": (
                            "https://grovealliance.org/fhir/withings/StructureDefinition/"
                            "withings-observation"
                        ),
                    },
                ],
            },
            "exchange-protocol.json": {
                **base,
                "extensions": {
                    "entryNodeKey": (
                        "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                        "grove-exchange-entry-node-key"
                    )
                },
                "entryIdentity": {
                    "fullUrl": {
                        "algorithm": "UUID version 5 over length-framed system and value",
                        "namespace": "43df4575-bff7-5a57-9a80-2472cd2b0623",
                    }
                },
                "lifecycle": {
                    "active": {
                        "entryResourcePolicy": {
                            "outputResourceTypes": [
                                "Observation",
                                "DocumentReference",
                                "Specimen",
                                "VisionPrescription",
                                "MedicationAdministration",
                                "MedicationStatement",
                            ],
                            "supportingResourceTypes": [
                                "Patient",
                                "Device",
                                "ResearchStudy",
                                "ResearchSubject",
                                "PlanDefinition",
                                "QuestionnaireResponse",
                            ],
                            "lifecycleResourceType": "Provenance",
                            "otherResourceTypesAllowed": False,
                            "containedResourcesAllowed": False,
                            "supportingResourcesMustBeConnected": True,
                        },
                        "adapterOnlyOutputProfileClaims": {
                            "resourceTypes": [
                                "Specimen",
                                "VisionPrescription",
                                "MedicationAdministration",
                                "MedicationStatement",
                            ]
                        }
                    }
                },
                "profiles": {
                    "conversionProvenance": (
                        "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                        "grove-mobile-conversion-provenance"
                    ),
                    "retractionProvenance": (
                        "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                        "grove-mobile-retraction-provenance"
                    ),
                },
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

        self.assertIn("public enum HealthKitContract", generated)
        self.assertIn('public static let catalogVersion = "0.6.0"', generated)
        self.assertIn("HKDataTypeIdentifierElectrocardiogram", generated)
        self.assertIn("HKQuantityTypeIdentifierBodyMassIndex", generated)
        self.assertIn("public static let bodyMassIndexProfiles", generated)
        self.assertIn("public static let electrocardiogramProfiles", generated)
        self.assertIn("public static let sourceTypeExtension", generated)
        self.assertNotIn("electrocardiogramCorrelatedSymptomExtension", generated)
        self.assertIn("public static let applicationDeviceProfile", generated)
        self.assertIn("public static let appleBundleIdentifierSystem", generated)
        self.assertIn('public static let appleBundleIdentifierTypeCode = "apple-bundle-id"', generated)
        self.assertIn("public static let clinicalRecordProfile", generated)
        self.assertNotIn("clinicalFHIRReleaseExtension", generated)
        self.assertIn('public static let clinicalFHIRPayloadFormatCode = "fhir-resource"', generated)
        self.assertIn("public static let admittedClinicalFHIRReleaseCodes: Set<String>", generated)
        self.assertIn("public static let clinicalFHIRContentTypeByRelease: [String: String]", generated)
        self.assertIn('        "dstu2",', generated)
        self.assertIn('        "r4",', generated)
        self.assertIn('        "dstu2": "application/fhir+json; fhirVersion=1.0",', generated)
        self.assertIn('        "r4": "application/fhir+json; fhirVersion=4.0",', generated)
        self.assertIn("public static let adapterOnlyOutputProfiles", generated)
        self.assertIn("public static let documentProfileModes", generated)
        self.assertIn("public static let deviceProfileModes", generated)
        self.assertIn("public static let activeProvenanceProfiles", generated)
        self.assertIn("public static let activeOutputResourceTypes", generated)
        self.assertIn("public static let containedResourcesAllowed = false", generated)
        self.assertIn('"Specimen": "https://grovealliance.org/fhir/health-connect/', generated)
        # Generated rows reference the profile constants this file defines rather than literals.
        self.assertIn("Profile.healthkitEcgObservation],", generated)
        # A quantity contract carries the catalog's canonical unit display.
        self.assertIn("unit:", generated)

    def test_rejects_unsorted_healthkit_inventory(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["rows"].reverse()

        with self.assertRaisesRegex(ValueError, "must be sorted"):
            self.generate(catalogs)

    def test_rejects_mismatched_clinical_release_representation(self):
        catalogs = self.catalogs()
        admission = catalogs["healthkit-adapter.json"]["clinicalRecordAdmission"]
        admission["admittedFHIRReleases"] = ["r4"]

        with self.assertRaisesRegex(ValueError, "exact DSTU2 or R4"):
            self.generate(catalogs)

    def test_rejects_unversioned_clinical_fhir_content_type(self):
        catalogs = self.catalogs()
        admission = catalogs["healthkit-adapter.json"]["clinicalRecordAdmission"]
        admission["fhirRepresentation"]["contentTypeByRelease"]["r4"] = (
            "application/fhir+json"
        )

        with self.assertRaisesRegex(ValueError, "exact DSTU2 or R4"):
            self.generate(catalogs)

    def test_rejects_unpaired_multi_measurement_healthkit_row(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["rows"][0]["measurementIDs"] = ["one", "two", "three"]

        with self.assertRaisesRegex(ValueError, "one profile per measurement"):
            self.generate(catalogs)

    def test_generates_paired_multi_measurement_healthkit_row(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["rows"][0]["measurementIDs"] = ["one", "two"]

        self.assertIn('measurementIDs: ["one", "two"],', self.generate(catalogs))

    def test_splits_measurement_catalog_by_owner(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["profiles"].append("grove-mobile-heart-rate")
        catalogs["package-graph.json"]["packages"][1]["profiles"].append("healthkit-symptom-headache")
        catalogs["measurement-catalog.json"]["measurements"] = [
            {
                "id": "heart-rate",
                "profile": "grove-mobile-heart-rate",
                "code": {"system": "http://loinc.org", "code": "8867-4"},
                "quantity": {
                    "system": "u",
                    "code": "/min",
                    "unit": "beats/minute",
                    "valueDomain": {
                        "minimum": {"value": 0, "inclusive": True},
                        "maximum": {"value": 300, "inclusive": False},
                        "integerOnly": True,
                    },
                },
                "effective": "dateTime",
            },
            {
                "id": "symptom-headache",
                "owner": "healthkit",
                "profile": "healthkit-symptom-headache",
                "code": {"system": "s", "code": "symptom-headache", "display": "Headache"},
                "quantity": None,
                "resultCodeSystem": "r",
                "allowedValues": ["not-present", "present"],
                "effective": "Period",
            },
            {
                "id": "step-cadence",
                "owner": "health-connect",
                "profile": "grove-mobile-heart-rate",
                "code": {"system": "s", "code": "step-cadence"},
                "quantity": None,
                "effective": "dateTime",
            },
        ]
        generated = self.generate(catalogs)

        mobile = generated.index("public enum MeasurementCatalog {")
        healthkit = generated.index("public enum HealthKitMeasurementCatalog {")
        self.assertLess(mobile, healthkit)
        self.assertLess(generated.index("let heartRate = MeasurementContract("), healthkit)
        self.assertGreater(generated.index("let symptomHeadache = MeasurementContract("), healthkit)
        self.assertIn('display: "Headache"', generated)
        self.assertIn(
            'QuantityValueDomain(minimum: QuantityBoundary(value: "0", inclusive: true), '
            'maximum: QuantityBoundary(value: "300", inclusive: false), integerOnly: true)',
            generated,
        )
        self.assertIn("    init(value lexical: String, inclusive: Bool) {", generated)
        self.assertNotIn("    public init(value lexical: String, inclusive: Bool) {", generated)
        self.assertIn("public func contains(_ value: Decimal) -> Bool", generated)
        self.assertNotIn("stepCadence", generated)

    def test_preserves_effective_datetime_or_period_choice(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["profiles"].append("grove-mobile-heart-rate")
        catalogs["measurement-catalog.json"]["measurements"] = [
            {
                "id": "heart-rate",
                "profile": "grove-mobile-heart-rate",
                "code": {"system": "http://loinc.org", "code": "8867-4"},
                "quantity": {"system": "http://unitsofmeasure.org", "code": "/min", "unit": "beats/minute"},
                "effective": "dateTime-or-Period",
            }
        ]

        generated = self.generate(catalogs)
        self.assertIn('case dateTimeOrPeriod = "dateTime-or-Period"', generated)
        self.assertIn("effective: .dateTimeOrPeriod", generated)

    def test_provider_owned_semantics_require_their_exact_envelope(self):
        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"] = [{
            "id": "oura-readiness-score",
            "owner": "oura",
            "profile": "oura-readiness-score",
            "code": {"system": "https://example.org/provider", "code": "readiness"},
            "quantity": None,
            "effective": "Period",
        }]

        generated = self.generate(catalogs)

        self.assertIn("public static let providerOwnedSemanticAdapters", generated)
        self.assertIn(
            '"https://grovealliance.org/fhir/oura/StructureDefinition/oura-readiness-score": '
            '"https://grovealliance.org/fhir/oura/StructureDefinition/oura-observation"',
            generated,
        )

    def test_generates_additional_required_measurement_codings(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["profiles"].append(
            "grove-mobile-resting-heart-rate"
        )
        catalogs["measurement-catalog.json"]["measurements"] = [{
            "id": "resting-heart-rate",
            "profile": "grove-mobile-resting-heart-rate",
            "code": {"system": "http://loinc.org", "code": "40443-4"},
            "requiredCodings": [{
                "slice": "heartRate",
                "system": "http://loinc.org",
                "code": "8867-4",
                "display": "Heart rate",
            }],
            "quantity": {
                "system": "http://unitsofmeasure.org",
                "code": "/min",
                "unit": "beats/minute",
            },
            "effective": "dateTime",
        }]

        generated = self.generate(catalogs)

        self.assertIn("public let requiredCodings: [CodingContract]", generated)
        self.assertIn(
            'CodingContract(system: "http://loinc.org", code: "8867-4", display: "Heart rate")',
            generated,
        )

    def test_rejects_unknown_effective_choice(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["profiles"].append("grove-mobile-heart-rate")
        catalogs["measurement-catalog.json"]["measurements"] = [
            {
                "id": "heart-rate",
                "profile": "grove-mobile-heart-rate",
                "code": {"system": "http://loinc.org", "code": "8867-4"},
                "quantity": None,
                "effective": "instant",
            }
        ]
        with self.assertRaisesRegex(ValueError, "unsupported effective choice"):
            self.generate(catalogs)


if __name__ == "__main__":
    unittest.main()
