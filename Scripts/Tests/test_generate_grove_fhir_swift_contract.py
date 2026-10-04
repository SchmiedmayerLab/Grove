#!/usr/bin/env python3
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT

import copy
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

UCUM = "http://unitsofmeasure.org"
VITAL_SIGNS = {
    "system": "http://terminology.hl7.org/CodeSystem/observation-category",
    "code": "vital-signs",
    "display": "Vital Signs",
}
HEART_RATE = {
    "id": "heart-rate",
    "profile": "grove-mobile-heart-rate",
    "code": {"system": "http://loinc.org", "code": "8867-4"},
    "category": VITAL_SIGNS,
    "quantity": {"system": UCUM, "code": "/min", "unit": "beats/minute"},
    "effective": "dateTime-or-Period",
}
BMI_PROFILE = "http://hl7.org/fhir/StructureDefinition/bmi"
HEALTHKIT_OBSERVATION = "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-observation"
SENSOR_ECG = "https://grovealliance.org/fhir/sensor/StructureDefinition/grove-sensor-ecg-observation"


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
                        "profiles": ["grove-mobile-exchange-bundle", "grove-mobile-heart-rate"],
                    },
                    {
                        "source": "healthkit",
                        "canonical": "https://grovealliance.org/fhir/healthkit",
                        "profiles": [
                            "healthkit-application-device",
                            "healthkit-conversion-provenance",
                            "healthkit-ecg-observation",
                            "healthkit-ecg-average-heart-rate-observation",
                            "healthkit-observation",
                        ],
                    },
                    {"source": "health-connect", "canonical": "https://grovealliance.org/fhir/health-connect", "profiles": []},
                    {"source": "oura", "canonical": "https://grovealliance.org/fhir/oura", "profiles": []},
                ],
            },
            "measurement-catalog.json": {
                **base,
                "statusVocabulary": ["supported", "deferred"],
                "measurements": [copy.deepcopy(HEART_RATE)],
            },
            "sensor-catalog.json": {
                **base,
                "contracts": [
                    {"id": "sampled-data", "profile": "grove-sensor-sampled-data-observation"},
                    {"id": "ecg", "profile": SENSOR_ECG, "code": {"system": "http://loinc.org", "code": "11524-6"}},
                ],
            },
            "terminology/loinc-concepts.json": {
                "concepts": {
                    "11524-6": {"display": "EKG study"},
                    "39156-5": {"display": "Body mass index (BMI) [Ratio]"},
                    "8867-4": {"display": "Heart rate"},
                },
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
                    "standardAdapterClaims": [
                        {"semanticProfile": BMI_PROFILE, "adapterProfile": HEALTHKIT_OBSERVATION},
                    ],
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
                "standardAdapterClaims": {
                    "body-mass-index": {
                        "claimMode": "exactly-standard-plus-adapter",
                        "profiles": [BMI_PROFILE, HEALTHKIT_OBSERVATION],
                        "code": {"system": "http://loinc.org", "code": "39156-5"},
                        "quantity": {"system": UCUM, "code": "kg/m2", "unit": "kg/m2"},
                        "effective": "dateTime",
                    }
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
                        "outputs": [
                            {
                                "outputRole": "electrocardiogram",
                                "outputDiscriminator": "single",
                                "profiles": [
                                    "https://grovealliance.org/fhir/sensor/StructureDefinition/"
                                    "grove-sensor-ecg-observation",
                                    "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                                    "healthkit-ecg-observation",
                                ],
                            },
                            {
                                "outputRole": "average-heart-rate",
                                "outputDiscriminator": "single",
                                "profiles": [
                                    "https://grovealliance.org/fhir/mobile/StructureDefinition/"
                                    "grove-mobile-heart-rate",
                                    "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                                    "healthkit-ecg-average-heart-rate-observation",
                                ],
                                "code": {"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"},
                                "quantity": {"system": UCUM, "code": "/min", "unit": "beats/minute"},
                            },
                        ],
                        "sourceLead": "HKElectrocardiogram.Lead.appleWatchSimilarToLeadI",
                        "leadCode": {
                            "system": "urn:iso:std:iso:11073:10101",
                            "code": "131329",
                            "display": "MDC_ECG_ELEC_POTL_I",
                        },
                        "quantity": {"system": UCUM, "code": "mV", "unit": "mV"},
                        "closedValueMappings": {
                            "classification": {
                                "sourceField": "HKElectrocardiogram.classification",
                                "r4Element": "Observation.interpretation",
                                "system": (
                                    "https://grovealliance.org/fhir/healthkit/CodeSystem/"
                                    "healthkit-ecg-classification"
                                ),
                                "values": [
                                    {"sourceValue": "notSet", "code": "notSet"},
                                    {"sourceValue": "sinusRhythm", "code": "sinusRhythm"},
                                ],
                            },
                            "symptomsStatus": {
                                "sourceField": "HKElectrocardiogram.symptomsStatus",
                                "r4Element": "healthkit-ecg-symptoms-status.valueCode",
                                "system": (
                                    "https://grovealliance.org/fhir/healthkit/CodeSystem/"
                                    "healthkit-ecg-symptoms-status"
                                ),
                                "values": [
                                    {"sourceValue": "none", "code": "none"},
                                    {"sourceValue": "present", "code": "present"},
                                ],
                            },
                            "algorithmVersion": {
                                "sourceField": "HKMetadataKeyAppleECGAlgorithmVersion",
                                "r4Element": "Observation.method",
                                "system": (
                                    "https://grovealliance.org/fhir/healthkit/CodeSystem/"
                                    "healthkit-ecg-algorithm-version"
                                ),
                                "values": [{"sourceValue": "1", "code": "version1"}],
                            },
                        },
                        "correlatedSymptomEvidence": {
                            "url": "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-ecg-correlated-symptom",
                            "sourceTypes": ["HKCategoryTypeIdentifierFatigue"],
                        },
                    }
                },
                "rows": [
                    {
                        "sourceTypeIdentifier": "HKCategoryTypeIdentifierFatigue",
                        "title": "Fatigue",
                        "status": "supported",
                        "measurementIDs": ["symptom-fatigue"],
                        "profiles": [
                            "https://grovealliance.org/fhir/healthkit/StructureDefinition/"
                            "healthkit-symptom-fatigue"
                        ],
                        "requirement": None,
                    },
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
                    },
                    "entryNode": {
                        "recommendedSystemForm": "<deployment-root>/NamingSystem/grove-entry-node-v0",
                    },
                },
                "lifecycle": {
                    "active": {
                        "studyContext": {
                            "entryNodeRoles": ["patient", "research-study", "research-subject", "plan-definition"],
                        },
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
                "producerDiagnostics": [
                    {
                        "code": "mobile-exchange.entry-node-key",
                        "emittedBy": "conformance-kit",
                        "reason": "Every Bundle entry must carry exactly one complete Grove exchange entry node key.",
                    },
                    {
                        "code": "mobile-input.unclassified",
                        "emittedBy": "client",
                        "reason": "A producer refused a source record without a more specific registered input rule.",
                    },
                    {
                        "code": "mobile-omission.recording-device",
                        "emittedBy": "client",
                        "severity": "warning",
                        "reason": "The source names a recording device without a stable per-unit token.",
                    },
                ],
                "opaqueIdentity": {
                    "recommendedSystemForm": (
                        "<deployment-root>/NamingSystem/grove-<identity-kind>-v0/<key-id>/<epoch>"
                    ),
                    "componentRequirements": {"unsignedDecimal": ["part-index"]},
                    "identityKinds": [
                        {
                            "kind": "source-artifact",
                            "identifierRole": "source-artifact",
                            "components": ["adapter-id", "format-code", "part-index"],
                        },
                    ],
                },
                "event": {
                    "bundleIdentifier": {
                        "recommendedSystemForm": "<deployment-root>/NamingSystem/grove-event-v0",
                    },
                },
                "payload": {
                    "equality": {
                        "vectors": "Conformance/corpora/receiver-lifecycle: reformatted-retry and lexeme-retry",
                    },
                },
            },
        }

    def electrocardiogram_row(self, catalogs: dict[str, dict]) -> dict:
        return next(
            row for row in catalogs["healthkit-adapter.json"]["rows"]
            if row["sourceTypeIdentifier"] == "HKDataTypeIdentifierElectrocardiogram"
        )

    def generate(self, catalogs: dict[str, dict]) -> str:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in catalogs.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(json.dumps(value), encoding="utf-8")
            return MODULE.generate(root)

    def generate_healthkit(self, catalogs: dict[str, dict]) -> str:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in catalogs.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(json.dumps(value), encoding="utf-8")
            return MODULE.generate_healthkit(root)

    def test_rejects_catalogs_of_different_versions(self):
        for name in MODULE.CATALOGS:
            catalogs = self.catalogs()
            catalogs[name]["version"] = "999.0.0"

            with self.subTest(catalog=name):
                with self.assertRaisesRegex(ValueError, f"different versions: .*'{name}': '999.0.0'"):
                    self.generate(catalogs)
                with self.assertRaisesRegex(ValueError, f"different versions: .*'{name}': '999.0.0'"):
                    self.generate_healthkit(catalogs)

    def test_generates_every_registered_rule_with_its_reason_and_severity(self):
        generated = self.generate(self.catalogs())

        self.assertIn("public enum ExchangeGraphRule: String, CaseIterable, Sendable", generated)
        self.assertIn('case mobileExchangeEntryNodeKey = "mobile-exchange.entry-node-key"', generated)
        self.assertIn('case mobileInputUnclassified = "mobile-input.unclassified"', generated)
        self.assertIn('case mobileOmissionRecordingDevice = "mobile-omission.recording-device"', generated)
        self.assertIn("case .mobileOmissionRecordingDevice:\n            .warning", generated)
        self.assertIn("case .mobileExchangeEntryNodeKey, .mobileInputUnclassified:\n            .error", generated)
        self.assertIn(
            '"Every Bundle entry must carry exactly one complete Grove exchange entry node key."',
            generated,
        )

    def test_generates_identifier_system_forms_study_roles_and_equality_vectors(self):
        generated = self.generate(self.catalogs())

        self.assertIn(
            'public static let opaqueIdentitySystemForm = '
            '"<deployment-root>/NamingSystem/grove-<identity-kind>-v0/<key-id>/<epoch>"',
            generated,
        )
        self.assertIn(
            'public static let eventIdentifierSystemForm = "<deployment-root>/NamingSystem/grove-event-v0"',
            generated,
        )
        self.assertIn(
            'public static let entryNodeIdentifierSystemForm = "<deployment-root>/NamingSystem/grove-entry-node-v0"',
            generated,
        )
        self.assertIn('case researchStudy = "research-study"', generated)
        self.assertIn('public static let equalityFormattingVector = "reformatted-retry"', generated)
        self.assertIn('public static let equalityDecimalLexemeVector = "lexeme-retry"', generated)
        self.assertIn('public static let equalityVectorCorpus = "Conformance/corpora/receiver-lifecycle"', generated)

    def test_generates_the_opaque_identity_component_rules(self):
        generated = self.generate(self.catalogs())

        self.assertIn('        case .sourceArtifact:\n            ["adapter-id", "format-code", "part-index"]', generated)
        self.assertIn("        case .sourceArtifact: .sourceArtifact", generated)
        self.assertIn('static let unsignedDecimalComponents: Set<String> = ["part-index"]', generated)

    def test_rejects_an_unsigned_decimal_rule_for_no_identity_component(self):
        catalogs = self.catalogs()
        catalogs["exchange-protocol.json"]["opaqueIdentity"]["componentRequirements"]["unsignedDecimal"] = ["ordinal"]

        with self.assertRaisesRegex(ValueError, "not identity components"):
            self.generate(catalogs)

    def test_rejects_rules_whose_codes_collapse_to_one_swift_case(self):
        catalogs = self.catalogs()
        catalogs["exchange-protocol.json"]["producerDiagnostics"].append(
            {"code": "mobile-exchange.entry.node-key", "emittedBy": "client", "reason": "Duplicate."}
        )

        with self.assertRaisesRegex(ValueError, "same Swift case"):
            self.generate(catalogs)

    def test_generates_the_healthkit_source_type_inventory(self):
        generated = self.generate_healthkit(self.catalogs())

        self.assertIn("public enum HealthKitSourceType: String, CaseIterable, Sendable", generated)
        self.assertIn('case electrocardiogram = "HKDataTypeIdentifierElectrocardiogram"', generated)
        self.assertIn('case bodyMassIndex = "HKQuantityTypeIdentifierBodyMassIndex"', generated)
        self.assertIn("public init?(_ sample: HKSample)", generated)

    def test_source_type_names_read_as_swift(self):
        self.assertEqual(MODULE.healthkit_source_type_name("HKQuantityTypeIdentifierVO2Max"), "vo2Max")
        self.assertEqual(MODULE.healthkit_source_type_name("HKWorkoutTypeIdentifier"), "workout")
        self.assertEqual(MODULE.healthkit_source_type_name("HKDocumentTypeIdentifierCDA"), "cda")
        self.assertEqual(MODULE.healthkit_source_type_name("HKDataTypeStateOfMind"), "stateOfMind")
        self.assertEqual(MODULE.healthkit_source_type_name("HKQuantityTypeIdentifierUVExposure"), "uvExposure")

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
        self.electrocardiogram_row(catalogs)["measurementIDs"] = ["one", "two", "three"]

        with self.assertRaisesRegex(ValueError, "one profile per measurement"):
            self.generate(catalogs)

    def test_generates_paired_multi_measurement_healthkit_row(self):
        catalogs = self.catalogs()
        self.electrocardiogram_row(catalogs)["measurementIDs"] = ["one", "two"]

        self.assertIn('measurementIDs: ["one", "two"],', self.generate(catalogs))

    def test_splits_measurement_catalog_by_owner(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][1]["profiles"].append("healthkit-symptom-headache")
        catalogs["measurement-catalog.json"]["measurements"] = [
            {
                "id": "heart-rate",
                "profile": "grove-mobile-heart-rate",
                "code": {"system": "http://loinc.org", "code": "8867-4"},
                "quantity": {
                    "system": UCUM,
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
        catalogs["measurement-catalog.json"]["measurements"].append({
            "id": "oura-readiness-score",
            "owner": "oura",
            "profile": "oura-readiness-score",
            "code": {"system": "https://example.org/provider", "code": "readiness"},
            "quantity": None,
            "effective": "Period",
        })

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
        catalogs["measurement-catalog.json"]["measurements"].append({
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
        })

        generated = self.generate(catalogs)

        self.assertIn("public let requiredCodings: [CodingContract]", generated)
        self.assertIn(
            'CodingContract(system: "http://loinc.org", code: "8867-4", display: "Heart rate")',
            generated,
        )

    def test_rejects_unknown_effective_choice(self):
        catalogs = self.catalogs()
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

    def test_generates_the_category_a_measurement_fixes_as_package_state(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["profiles"].append("grove-mobile-step-count")
        catalogs["measurement-catalog.json"]["measurements"].append({
            "id": "step-count",
            "profile": "grove-mobile-step-count",
            "code": {"system": "http://loinc.org", "code": "55423-8"},
            "quantity": None,
            "effective": "Period",
        })

        generated = self.generate(catalogs)

        self.assertIn("    package let category: CodingContract?\n}", generated)
        self.assertIn(
            '        effective: .dateTimeOrPeriod,\n'
            '        category: CodingContract(system: "http://terminology.hl7.org/CodeSystem/observation-category", '
            'code: "vital-signs", display: "Vital Signs")\n    )',
            generated,
        )
        self.assertIn("        effective: .period,\n        category: nil\n    )", generated)

    def test_generates_the_body_mass_index_contract_from_its_standard_claim(self):
        generated = self.generate(self.catalogs())

        self.assertIn(
            "    package static let bodyMassIndex = MeasurementContract(\n"
            '        id: "body-mass-index",\n'
            '        profile: "http://hl7.org/fhir/StructureDefinition/bmi",\n'
            '        code: CodingContract(system: "http://loinc.org", code: "39156-5"),\n'
            "        requiredCodings: [],\n"
            '        quantity: QuantityContract(system: "http://unitsofmeasure.org", code: "kg/m2", unit: "kg/m2", '
            "valueDomain: nil),\n"
            "        components: [],\n"
            "        resultCodeSystem: nil,\n"
            "        allowedValues: [],\n"
            "        resultCodes: [],\n"
            "        method: nil,\n"
            "        methodChoice: [],\n"
            "        effective: .dateTime,\n"
            "        category: nil\n"
            "    )\n",
            generated,
        )
        self.assertLess(generated.index("public enum HealthKitContract {"), generated.index("let bodyMassIndex ="))
        self.assertNotIn("        bodyMassIndex,", generated)

    def test_rejects_a_body_mass_index_claim_its_row_does_not_state(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["standardAdapterClaims"]["body-mass-index"]["profiles"].reverse()

        with self.assertRaisesRegex(ValueError, "registered standard-plus-adapter claim"):
            self.generate(catalogs)

        catalogs = self.catalogs()
        catalogs["profile-claims.json"]["observationAdapterClaim"]["standardAdapterClaims"] = []

        with self.assertRaisesRegex(ValueError, "registered standard-plus-adapter claim"):
            self.generate(catalogs)

    def test_rejects_a_catalog_measurement_named_body_mass_index(self):
        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"].append(
            {**HEART_RATE, "id": "body-mass-index", "category": None}
        )

        with self.assertRaisesRegex(ValueError, "not a catalog measurement"):
            self.generate(catalogs)

    def test_rejects_a_body_mass_index_claim_in_another_mode(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["standardAdapterClaims"]["body-mass-index"]["claimMode"] = (
            "exactly-shared-plus-adapter"
        )

        with self.assertRaisesRegex(ValueError, "registered standard-plus-adapter claim"):
            self.generate(catalogs)

    def test_names_the_body_mass_index_contract_whatever_its_claim_states(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["standardAdapterClaims"]["body-mass-index"]["id"] = "bmi"
        generated = self.generate(catalogs)

        self.assertIn('    package static let bodyMassIndex = MeasurementContract(\n        id: "body-mass-index",', generated)
        self.assertNotIn("let bmi =", generated)

    def test_rejects_adapter_claims_the_generator_does_not_read(self):
        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["standardAdapterClaims"]["blood-pressure"] = {}

        with self.assertRaisesRegex(ValueError, r"standard adapter claims \['blood-pressure', 'body-mass-index'\]"):
            self.generate(catalogs)

        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["sensorAdapterClaims"]["audiogram"] = {}

        with self.assertRaisesRegex(ValueError, r"sensor adapter claims \['audiogram', 'electrocardiogram'\]"):
            self.generate(catalogs)

    def test_rejects_a_category_without_system_and_code(self):
        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"][0]["category"] = {}

        with self.assertRaisesRegex(ValueError, "a coding must state its system and code: {}"):
            self.generate(catalogs)

    def test_places_each_measurement_profile_under_its_owners_package(self):
        catalogs = self.catalogs()
        catalogs["package-graph.json"]["packages"][0]["canonical"] = "https://example.org/fhir/mobile"
        heart_rate = "https://example.org/fhir/mobile/StructureDefinition/grove-mobile-heart-rate"
        claim = catalogs["healthkit-adapter.json"]["sensorAdapterClaims"]["electrocardiogram"]
        claim["outputs"][1]["profiles"][0] = heart_rate

        self.assertIn("    static let averageHeartRateMeasurement = MeasurementCatalog.heartRate", self.generate_healthkit(catalogs))

        catalogs["measurement-catalog.json"]["measurements"].append({**HEART_RATE, "id": "pulse"})

        with self.assertRaisesRegex(ValueError, f"measurements 'heart-rate' and 'pulse' both claim {heart_rate}"):
            self.generate_healthkit(catalogs)

        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"][0]["owner"] = "fitbit"

        with self.assertRaisesRegex(ValueError, "'heart-rate' is owned by 'fitbit', which no package declares"):
            self.generate(catalogs)

    def test_generates_the_electrocardiogram_claim_typed_against_healthkit(self):
        generated = self.generate_healthkit(self.catalogs())

        self.assertIn("import GroveFHIRContract\npublic import HealthKit\nimport ModelsR4\n", generated)
        self.assertIn("@available(iOS 18, macOS 15, watchOS 11, *)\nenum HealthKitElectrocardiogramClaim {", generated)
        self.assertIn(
            "    static let waveform = Output(\n"
            '        role: "electrocardiogram",\n'
            '        discriminator: "single",\n'
            "        profiles: HealthKitContract.electrocardiogramProfiles\n"
            "    )",
            generated,
        )
        self.assertIn(
            "    static let averageHeartRate = Output(\n"
            '        role: "average-heart-rate",\n'
            '        discriminator: "single",\n'
            "        profiles: [Profile.groveMobileHeartRate, Profile.healthkitEcgAverageHeartRateObservation]\n"
            "    )",
            generated,
        )
        self.assertIn(
            '    static let averageHeartRateCode = CodingContract(system: "http://loinc.org", code: "8867-4", '
            'display: "Heart rate")',
            generated,
        )
        self.assertIn("    static let averageHeartRateMeasurement = MeasurementCatalog.heartRate", generated)
        self.assertIn("    static let sourceLead = HKElectrocardiogram.Lead.appleWatchSimilarToLeadI", generated)
        self.assertIn(
            '    static let leadCode = CodingContract(system: "urn:iso:std:iso:11073:10101", '
            'code: "131329", display: "MDC_ECG_ELEC_POTL_I")',
            generated,
        )
        self.assertIn(
            '    static let voltageQuantity = QuantityContract(system: "http://unitsofmeasure.org", '
            'code: "mV", unit: "mV", valueDomain: nil)',
            generated,
        )
        self.assertIn(
            '    static let classificationSystem = "https://grovealliance.org/fhir/healthkit/CodeSystem/'
            'healthkit-ecg-classification"\n'
            "    /// The Observation.interpretation code of each HKElectrocardiogram.classification the guide admits.\n"
            "    static let classificationCodes: [HKElectrocardiogram.Classification: String] = [\n"
            '        HKElectrocardiogram.Classification.notSet: "notSet",\n'
            '        HKElectrocardiogram.Classification.sinusRhythm: "sinusRhythm",\n'
            "    ]",
            generated,
        )
        self.assertIn(
            "    static let symptomsStatusCodes: [HKElectrocardiogram.SymptomsStatus: String] = [\n"
            '        HKElectrocardiogram.SymptomsStatus.none: "none",\n'
            '        HKElectrocardiogram.SymptomsStatus.present: "present",\n'
            "    ]",
            generated,
        )
        self.assertIn(
            '    static let algorithmVersionSystem = "https://grovealliance.org/fhir/healthkit/CodeSystem/'
            'healthkit-ecg-algorithm-version"\n'
            "    /// The Observation.method code of each HKMetadataKeyAppleECGAlgorithmVersion the guide admits.\n"
            "    static let algorithmVersionCodes: [Int: String] = [\n"
            '        1: "version1",\n'
            "    ]",
            generated,
        )
        self.assertIn(
            "    static let correlatedSymptomSourceTypes: Set<HealthKitSourceType> = [\n"
            "        .fatigue,\n"
            "    ]\n"
            "}\n"
            "\n"
            "#endif\n",
            generated,
        )
        self.assertNotIn("package ", generated)
        # The platform-neutral contract keeps only the public ECG profiles the waveform output names.
        contract = self.generate(self.catalogs())
        self.assertNotIn("HealthKitElectrocardiogramClaim", contract)
        self.assertNotIn("ClosedValueMappingContract", contract)

    def test_generates_the_guide_display_of_each_code_a_row_states_without_one(self):
        generated = self.generate_healthkit(self.catalogs())

        self.assertIn(
            "enum HealthKitTerminology {\n"
            "    /// The display of each such code.\n"
            "    static let displays: [CodingContract: String] = [\n"
            '        CodingContract(system: "http://loinc.org", code: "39156-5"): "Body mass index (BMI) [Ratio]",\n'
            "    ]\n"
            "}\n",
            generated,
        )
        self.assertIn(
            '    static let waveformCode = CodingContract(system: "http://loinc.org", code: "11524-6", '
            'display: "EKG study")',
            generated,
        )

        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"].append(
            {**HEART_RATE, "id": "symptom-fatigue", "profile": "healthkit-symptom-fatigue", "category": None}
        )
        generated = self.generate_healthkit(catalogs)

        self.assertIn('        CodingContract(system: "http://loinc.org", code: "8867-4"): "Heart rate",\n', generated)

    def test_rejects_a_code_the_guide_states_no_display_for(self):
        catalogs = self.catalogs()
        catalogs["terminology/loinc-concepts.json"]["concepts"].pop("39156-5")

        with self.assertRaisesRegex(ValueError, "body-mass-index code .* is no LOINC concept"):
            self.generate_healthkit(catalogs)

        catalogs = self.catalogs()
        catalogs["healthkit-adapter.json"]["standardAdapterClaims"]["body-mass-index"]["code"]["system"] = "urn:other"

        with self.assertRaisesRegex(ValueError, "body-mass-index code .* is no LOINC concept"):
            self.generate_healthkit(catalogs)

        catalogs = self.catalogs()
        catalogs["terminology/loinc-concepts.json"]["concepts"].pop("11524-6")

        with self.assertRaisesRegex(ValueError, "HealthKit ECG waveform code .* is no LOINC concept"):
            self.generate_healthkit(catalogs)

    def test_rejects_an_electrocardiogram_profile_no_single_coded_sensor_contract_has(self):
        catalogs = self.catalogs()
        catalogs["sensor-catalog.json"]["contracts"][1].pop("code")

        with self.assertRaisesRegex(ValueError, "is no single coded sensor contract's"):
            self.generate_healthkit(catalogs)

        catalogs = self.catalogs()
        catalogs["sensor-catalog.json"]["contracts"].append({"id": "ecg-copy", "profile": SENSOR_ECG, "code": {}})

        with self.assertRaisesRegex(ValueError, "is no single coded sensor contract's"):
            self.generate_healthkit(catalogs)

    def electrocardiogram_claim(self, catalogs: dict[str, dict]) -> dict:
        return catalogs["healthkit-adapter.json"]["sensorAdapterClaims"]["electrocardiogram"]

    def assert_refuses_electrocardiogram_claim(self, change, message: str) -> None:
        catalogs = self.catalogs()
        change(self.electrocardiogram_claim(catalogs))

        with self.assertRaisesRegex(ValueError, message):
            self.generate_healthkit(catalogs)

    def test_rejects_electrocardiogram_outputs_other_than_waveform_and_average_heart_rate(self):
        def rename(role: str):
            return lambda claim: claim["outputs"][1].update(outputRole=role)

        self.assert_refuses_electrocardiogram_claim(lambda claim: claim["outputs"].pop(), r"declares no \['average-heart-rate'\]")
        self.assert_refuses_electrocardiogram_claim(rename("electrocardiogram"), "'electrocardiogram' is declared twice")
        self.assert_refuses_electrocardiogram_claim(rename("pulse"), "output role 'pulse' is not one of")
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][0]["profiles"].pop(), "waveform output must claim exactly"
        )

    def test_rejects_an_average_heart_rate_that_restates_its_measurement_differently(self):
        average_heart_rate = "average heart rate"
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1]["quantity"].update(code="/s"), f"{average_heart_rate} quantity"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1]["quantity"].pop("unit"), f"{average_heart_rate} quantity"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1]["quantity"].update(valueDomain={}), f"{average_heart_rate} quantity"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1].update(quantity={}), f"{average_heart_rate} quantity {{}}"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1].pop("quantity"), f"{average_heart_rate} quantity None"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["outputs"][1]["code"].update(code="8893-0"), f"{average_heart_rate} code"
        )

        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"][0]["code"]["display"] = "Pulse"

        with self.assertRaisesRegex(ValueError, f"{average_heart_rate} code"):
            self.generate_healthkit(catalogs)

        catalogs = self.catalogs()
        catalogs["measurement-catalog.json"]["measurements"] = []

        with self.assertRaisesRegex(ValueError, "profile '.*grove-mobile-heart-rate' is no generated measurement's"):
            self.generate_healthkit(catalogs)

    def test_rejects_electrocardiogram_value_mappings_it_cannot_type(self):
        def mapping(name: str, **change):
            return lambda claim: claim["closedValueMappings"][name].update(**change)

        def value(name: str, **change):
            return lambda claim: claim["closedValueMappings"][name]["values"][0].update(**change)

        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["closedValueMappings"].pop("classification"), "mappings .* are not exactly"
        )
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["closedValueMappings"].update(default={}), r"mappings \['algorithmVersion', .*'default'"
        )
        self.assert_refuses_electrocardiogram_claim(mapping("symptomsStatus", values=[]), "map at least one source value")
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim["closedValueMappings"]["algorithmVersion"]["values"].append(
                {"sourceValue": "1", "code": "version2"}
            ),
            "'algorithmVersion' mapping maps source value '1' twice",
        )
        self.assert_refuses_electrocardiogram_claim(value("algorithmVersion", sourceValue="01"), "'01' is not a canonical")
        self.assert_refuses_electrocardiogram_claim(value("algorithmVersion", sourceValue=1), "string source value")
        self.assert_refuses_electrocardiogram_claim(value("classification", code=None), "to a string code")
        self.assert_refuses_electrocardiogram_claim(
            value("classification", sourceValue="default"), "'default' cannot name a HKElectrocardiogram.Classification"
        )
        self.assert_refuses_electrocardiogram_claim(value("symptomsStatus", sourceValue="not-set"), "'not-set' cannot name")
        self.assert_refuses_electrocardiogram_claim(
            lambda claim: claim.update(sourceLead="HKElectrocardiogram.Lead.default"), "source lead"
        )
        self.assert_refuses_electrocardiogram_claim(lambda claim: claim.pop("sourceLead"), "source lead None")

    def test_rejects_electrocardiogram_symptom_types_that_are_not_distinct_inventory_rows(self):
        def symptoms(source_types: list):
            return lambda claim: claim["correlatedSymptomEvidence"].update(sourceTypes=source_types)

        fatigue = "HKCategoryTypeIdentifierFatigue"
        self.assert_refuses_electrocardiogram_claim(symptoms([]), "admits no correlated symptom")
        self.assert_refuses_electrocardiogram_claim(symptoms([fatigue, fatigue]), f"'{fatigue}' is listed twice")
        self.assert_refuses_electrocardiogram_claim(
            symptoms([fatigue, "HKCategoryTypeIdentifierDizziness"]), "'HKCategoryTypeIdentifierDizziness' is not an"
        )


if __name__ == "__main__":
    unittest.main()
