//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Entry points precede their static parsing helpers so the clinical pass-through reads top-down.
// swiftlint:disable type_contents_order cyclomatic_complexity

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveFHIRContract
public import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Converts the exact provider-issued R4 JSON bytes surfaced by HealthKit into one validated
    /// Grove exchange graph. Grove decodes only to prove the registered payload shape and never
    /// re-encodes or claims conformance over the provider's resource.
    public func convert(
        _ record: HKClinicalRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitDocumentConversion {
        do {
            guard let fhirResource = record.fhirResource else {
                throw HealthKitConversionError.clinicalRecordWithoutResource(record.uuid)
            }
            guard !fhirResource.data.isEmpty else {
                throw HealthKitConversionError.undecodableClinicalRecord(record.uuid)
            }
            _ = try Self.decodeR4ClinicalResource(
                data: fhirResource.data,
                release: fhirResource.fhirVersion.fhirRelease,
                versionDescription: fhirResource.fhirVersion.stringRepresentation,
                sourceUUID: record.uuid
            )
            return try Self.assembleDocumentGraph(
                for: record,
                evidence: HealthKitRecordingEvidence(
                    outputRole: "clinical-record",
                    format: .fhirR4Resource,
                    title: HealthKitCatalog.entry(forSourceTypeIdentifier: record.sampleType.identifier)?.title
                        ?? "Clinical FHIR resource",
                    payload: fhirResource.data,
                    profiles: [HealthKitContract.clinicalRecordProfile],
                    clinicalRecordTypeCode: try Self.clinicalRecordTypeCode(
                        sourceTypeIdentifier: record.sampleType.identifier
                    ),
                    clinicalFHIRReleaseCode: HealthKitContract.clinicalFHIRReleaseCode
                ),
                context: context
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Carries one CDA document exactly as HealthKit delivered it.
    ///
    /// The bytes are another issuer's document. Grove identifies it and records who wrote it, and
    /// never rewrites, reserializes, or asserts conformance over it — the same treatment a
    /// provider-issued clinical record receives.
    ///
    /// - Note: `HKCDADocumentSample.document` is populated only for a sample returned by an
    ///   `HKDocumentQuery` that asked for document data, so a sample from any other query fails
    ///   closed rather than converting to an empty payload.
    public func convert(
        _ sample: HKCDADocumentSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitDocumentConversion {
        do {
            guard let document = sample.document,
                  let data = document.documentData,
                  !data.isEmpty else {
                throw HealthKitConversionError.missingClinicalDocumentData(sample.uuid)
            }
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return try Self.assembleDocumentGraph(
                for: sample,
                evidence: HealthKitRecordingEvidence(
                    outputRole: "clinical-record",
                    format: .clinicalDocument,
                    title: title.isEmpty ? "Clinical document" : title,
                    payload: data
                ),
                context: context
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    private static func clinicalRecordTypeCode(
        sourceTypeIdentifier: String
    ) throws -> String {
        let code: String? = switch sourceTypeIdentifier {
        case "HKClinicalTypeIdentifierAllergyRecord": "allergy-record"
        case "HKClinicalTypeIdentifierClinicalNoteRecord": "clinical-note-record"
        case "HKClinicalTypeIdentifierConditionRecord": "condition-record"
        case "HKClinicalTypeIdentifierCoverageRecord": "coverage-record"
        case "HKClinicalTypeIdentifierImmunizationRecord": "immunization-record"
        case "HKClinicalTypeIdentifierLabResultRecord": "lab-result-record"
        case "HKClinicalTypeIdentifierMedicationRecord": "medication-record"
        case "HKClinicalTypeIdentifierProcedureRecord": "procedure-record"
        case "HKClinicalTypeIdentifierVitalSignRecord": "vital-sign-record"
        default: nil
        }
        guard let code else {
            throw HealthKitConversionError.unsupportedSampleType(sourceTypeIdentifier)
        }
        return code
    }
}

#endif
