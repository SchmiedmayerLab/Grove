//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


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
    case invalidSymptomSeverity(typeIdentifier: String, value: Int)
    case invalidSymptomPeriod(UUID)
    case invalidSymptomSourceRevision(sourceUUID: UUID, field: String)
    case symptomSourceDisclosureNotAuthorized
    case duplicateSymptomSource(UUID)
    case tooManySymptoms(Int)
    case unsupportedAlgorithmVersion(Int)
}


/// A fail-closed error from the R4 HealthKit conversion facade.
public enum GroveHealthKitFHIRError: Error, Equatable, Sendable {
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
    /// A required typed FHIR reference is empty or targets the wrong resource type.
    case invalidReference(field: String, expectedResourceType: String)
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
    /// A business identifier, deterministic fullUrl, or repository id was invalid.
    case invalidExchangeIdentity(String)
    /// An unexpected non-domain error occurred while converting one record in a batch.
    case unexpectedConversionFailure(String)
}
