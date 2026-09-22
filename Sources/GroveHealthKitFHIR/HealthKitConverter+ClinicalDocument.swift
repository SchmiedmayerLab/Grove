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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Carries the exact provider-issued DSTU2 or R4 JSON bytes surfaced by HealthKit in one
    /// validated R4 Grove exchange graph.
    ///
    /// The source release is mapped from `HKFHIRVersion.fhirRelease` to the attachment's versioned
    /// FHIR JSON media type. Grove validates only that the bytes contain one FHIR resource envelope;
    /// it never converts, re-encodes, or claims conformance over the provider's resource.
    public func convert(
        _ record: HKClinicalRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            return try Self.convertClinicalRecord(record, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: HealthKitSourceType(record))
        }
    }

    static func convertClinicalRecord(
        _ record: HKClinicalRecord,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversionSet {
        guard let fhirResource = record.fhirResource else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        let evidence = try clinicalRecordingEvidence(
            data: fhirResource.data,
            release: fhirResource.fhirVersion.fhirRelease,
            versionDescription: fhirResource.fhirVersion.stringRepresentation,
            sourceUUID: record.uuid,
            sourceTypeIdentifier: record.sampleType.identifier
        )
        return try assembleDocumentGraph(for: record, evidence: evidence, context: context)
    }

    static func clinicalRecordingEvidence(
        data: Data,
        release: HKFHIRRelease,
        versionDescription: String,
        sourceUUID: UUID,
        sourceTypeIdentifier: String
    ) throws(HealthKitConversionError) -> HealthKitRecordingEvidence {
        let releaseCode: String
        switch release {
        case .dstu2:
            releaseCode = "dstu2"
        case .r4:
            releaseCode = "r4"
        case .unknown:
            throw .clinicalRecord(.unsupportedRelease)
        default:
            throw .clinicalRecord(.unsupportedRelease)
        }
        guard HealthKitContract.admittedClinicalFHIRReleaseCodes.contains(releaseCode) else {
            throw .clinicalRecord(.unsupportedRelease)
        }
        do {
            try FHIRJSONResourcePayload.validate(data)
        } catch {
            throw .clinicalRecord(.undecodable)
        }
        return HealthKitRecordingEvidence(
            outputRole: "clinical-record",
            format: .fhirResource,
            title: HealthKitSourceType(rawValue: sourceTypeIdentifier).map { HealthKitCatalog[$0].title }
                ?? "Clinical FHIR resource",
            payload: data,
            profiles: [HealthKitContract.clinicalRecordProfile],
            clinicalRecordTypeCode: try clinicalRecordTypeCode(
                sourceTypeIdentifier: sourceTypeIdentifier
            ),
            clinicalFHIRReleaseCode: releaseCode
        )
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
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            return try Self.convertClinicalDocument(sample, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .cda)
        }
    }

    static func convertClinicalDocument(
        _ sample: HKCDADocumentSample,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversionSet {
        guard let document = sample.document,
              let data = document.documentData,
              !data.isEmpty else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return try assembleDocumentGraph(
            for: sample,
            evidence: HealthKitRecordingEvidence(
                outputRole: "clinical-record",
                format: .clinicalDocument,
                title: title.isEmpty ? "Clinical document" : title,
                payload: data
            ),
            context: context
        )
    }

    private static func clinicalRecordTypeCode(
        sourceTypeIdentifier: String
    ) throws(HealthKitConversionError) -> String {
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
            throw HealthKitSourceType(rawValue: sourceTypeIdentifier).map(HealthKitConversionError.unsupportedSourceType)
                ?? .unregisteredSourceType(sourceTypeIdentifier)
        }
        return code
    }
}

#endif
