//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
internal import GroveFHIRContract
public import ModelsR4


/// A fail-closed reason why caller-supplied HealthKit ECG evidence was rejected.
public enum HealthKitECGEvidenceFailure: Error, Equatable, Sendable {
    case invalidSourcePeriod
    case invalidReportedVoltageCount(Int)
    case voltageCountMismatch(reported: Int, supplied: Int)
    case insufficientVoltageMeasurements
    case invalidOffset(index: Int)
    case nonUniformOffset(index: Int)
    case missingLeadVoltage(index: Int)
    case invalidLeadVoltage(index: Int)
    case invalidAverageHeartRate
    case invalidSamplingFrequency
    case samplingFrequencyMismatch
    case unsupportedClassification(Int)
    case unsupportedSymptomsStatus(Int)
    case symptomsRequired
    case unexpectedSymptoms
    case unsupportedSymptomType(String)
    case duplicateSymptomSource(UUID)
    /// A companion conversion was produced for a different patient or repository scope.
    case mismatchedSymptomContext
    case invalidSymptomOutputIdentity
    case duplicateSymptomOutputIdentity
    case duplicateSymptomEventIdentity
    case unsupportedAlgorithmVersion(Int)
}


/// A fail-closed error from the R4 HealthKit conversion facade.
public enum HealthKitConversionError: Error, Equatable, Sendable {
    /// A source shape did not match its selected, published mapping.
    case invalidValue
    /// The SDK type has no admitted Grove profile intersection.
    case unsupportedSampleType(String)
    /// ECG conversion requires the caller to supply the complete voltage enumeration and
    /// any separately queried correlated symptom samples through the dedicated overload.
    case missingECGEvidence
    /// Caller-supplied ECG evidence is incomplete, internally inconsistent, or cannot be
    /// represented losslessly by the published adapter contract.
    case invalidECGEvidence(HealthKitECGEvidenceFailure)
    /// A required converter application field is empty.
    case invalidConverterApplication(String)
    /// A caller-classified HealthKit source application has no valid Apple bundle identifier.
    case invalidSourceApplication(String)
    /// A retained metadata value is present but not the type the key is defined to carry.
    case invalidMetadataValue(key: String)
    /// A required typed FHIR reference is empty or targets the wrong resource type.
    case invalidReference(field: String, expectedResourceType: ResourceType)
    /// A repeated reference would create ambiguous duplicate graph relationships.
    case duplicateReference(field: String)
    /// A mapped Observation has no normative code after adapter dispatch codings are removed.
    case missingNormativeCode(String)
    /// A period-total metric did not carry a positive source interval.
    case invalidEffectivePeriod(sampleType: String)
    /// A panel sample did not contain one of its required result components.
    case missingRequiredComponent(sampleType: String, component: String)
    /// A source value has no published mapping in the selected shared profile.
    case unsupportedSampleValue(sampleType: String, value: Int)
    /// A typed, allowlisted HealthKit metadata field contained a value outside its published value set.
    case unsupportedMetadataValue(key: String, value: String)
    /// A metadata field the selected contract requires was absent from the sample.
    case missingRequiredMetadata(sampleType: String, key: String)
    /// The frozen catalog intentionally rejects this source type for the stated catalog reason.
    case intentionallyUnsupported(sampleType: String, reason: String)
    /// A clinical record carried no FHIR resource, so there is nothing to read.
    case clinicalRecordWithoutResource(UUID)
    /// A clinical record's FHIR payload could not be decoded in the release it declares.
    case undecodableClinicalRecord(UUID)
    /// A clinical record declares a FHIR release this adapter does not read.
    case unsupportedClinicalRelease(String)
    /// A clinical record's attachment could not be read from the attachment store.
    case unreadableClinicalAttachment(UUID)
    /// A series carried as a recording document was handed no samples, so there is nothing to
    /// carry and no way to tell an empty series from a failed enumeration.
    case emptyRecordingSeries(sampleType: String)
    /// A CDA sample carried no document bytes, which a query that excludes document data returns.
    case missingClinicalDocumentData(UUID)
    /// A recording payload is larger than the attachment size FHIR can state.
    case recordingPayloadTooLarge(byteCount: Int)
    /// The source is admitted only as a platform-exclusive DocumentReference envelope, which
    /// this Observation converter never emits.
    case platformExclusiveDocument(sampleType: String)
    /// The catalog admits this source, but this converter version does not yet emit its graph.
    case notYetConvertible(sampleType: String)
    /// A panel component sample converts only inside its admitting correlation.
    case componentSampleRequiresCorrelation(sampleType: String)
    /// A business identifier, deterministic fullUrl, or repository id was invalid.
    case invalidExchangeIdentity(String)
    /// An unexpected non-domain error occurred while converting one record in a batch.
    /// A dependency raised a failure this domain does not model, named by type.
    ///
    /// Only the type is carried: a failing FHIR date conversion describes itself with the exact
    /// instant it could not convert, and that instant identifies a participant.
    case unexpectedConversionFailure(String)
}


extension HealthKitConversionError {
    /// Narrows any conversion failure to this published domain, so the converter's typed
    /// throws stay exhaustive even when a dependency raises its own error.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as HealthKitConversionError:
            self = error
        case let error as ExchangeIdentityError:
            self = .invalidExchangeIdentity(String(describing: error))
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
