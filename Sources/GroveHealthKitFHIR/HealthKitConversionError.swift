//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
import HealthKit


/// A fail-closed reason why caller-supplied HealthKit ECG evidence was rejected.
public enum HealthKitECGEvidenceFailure: Hashable, Sendable {
    /// An ECG reached the sample entry point; its voltages and symptoms travel through the ECG record.
    case evidenceRequired
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
    /// One context per correlated symptom sample, in the record's order.
    case symptomContextCountMismatch(symptoms: Int, contexts: Int)
    /// A companion context names a different subject, repository scope or identity scope.
    case mismatchedSymptomContext
    case invalidSymptomOutputIdentity
    case duplicateSymptomOutputIdentity
    case duplicateSymptomEventIdentity
    case unsupportedAlgorithmVersion(Int)
}


/// A HealthKit metadata key the adapter reads.
public enum HealthKitMetadataField: Hashable, Sendable, CaseIterable {
    case timeZone
    case syncIdentifier
    case syncVersion
    case wasUserEntered
    case heartRateMotionContext
    case insulinDeliveryReason
    case menstrualCycleStart
    case sexualActivityProtectionUsed
    case appleECGAlgorithmVersion

    /// The typed allowlist: every key the adapter models.
    static let keys = Set(allCases.map(\.key))

    public var key: String {
        switch self {
        case .timeZone: HKMetadataKeyTimeZone
        case .syncIdentifier: HKMetadataKeySyncIdentifier
        case .syncVersion: HKMetadataKeySyncVersion
        case .wasUserEntered: HKMetadataKeyWasUserEntered
        case .heartRateMotionContext: HKMetadataKeyHeartRateMotionContext
        case .insulinDeliveryReason: HKMetadataKeyInsulinDeliveryReason
        case .menstrualCycleStart: HKMetadataKeyMenstrualCycleStart
        case .sexualActivityProtectionUsed: HKMetadataKeySexualActivityProtectionUsed
        case .appleECGAlgorithmVersion: HKMetadataKeyAppleECGAlgorithmVersion
        }
    }
}


/// Why a source value did not fit its published mapping.
public enum HealthKitValueFailure: Error, Hashable, Sendable {
    /// The value's shape is not what the selected mapping requires.
    case shapeInvalid
    case outsideDomain
    /// An enumeration value with no published mapping.
    case unsupportedValue(Int)
    case unsupportedMetadataValue(HealthKitMetadataField)
    case invalidMetadataValue(HealthKitMetadataField)
    case requiredMetadataMissing(HealthKitMetadataField)
    /// A panel is missing one of its catalog components, named by the component id.
    case requiredComponentMissing(component: String)
    case effectivePeriodInvalid
    case emptyRecordingSeries
    case recordingPayloadTooLarge(byteCount: Int)
    /// The selected contract states no normative code for the value.
    case missingNormativeCode
}


/// Why a clinical record or CDA document could not be carried.
public enum HealthKitClinicalRecordFailure: Hashable, Sendable {
    /// No resource or document bytes, which a query that excludes document data returns.
    case empty
    /// The payload is not one FHIR JSON resource envelope.
    case undecodable
    /// A FHIR release other than DSTU2 or R4.
    case unsupportedRelease
    case unreadableAttachment
}


/// A failure raised by something this domain does not model, kept as it was raised.
///
/// Only the type is compared: a failing FHIR date conversion describes itself with the exact
/// instant it could not convert, and that instant identifies a participant.
public struct HealthKitDependencyFailure: Error, Equatable, Sendable {
    public let underlying: any Error

    public init(underlying: any Error) {
        self.underlying = underlying
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        String(reflecting: type(of: lhs.underlying)) == String(reflecting: type(of: rhs.underlying))
    }
}


/// A fail-closed refusal from the HealthKit conversion facade; every case reports one registry code.
public enum HealthKitConversionError: Error, Equatable, Sendable {
    /// The identifier is not in the adapter inventory at all.
    case unregisteredSourceType(String)
    case unsupportedSourceType(HealthKitSourceType)
    case intentionallyUnsupported(HealthKitSourceType, reason: String)
    case notYetConvertible(HealthKitSourceType)
    /// Admitted only as a platform-exclusive recording document, which this entry point does not emit.
    case platformExclusiveSourceType(HealthKitSourceType)
    /// A blood pressure component converts only inside its admitting correlation.
    case componentRequiresCorrelation(HealthKitSourceType)
    case invalidValue(HealthKitSourceType, HealthKitValueFailure)
    case ecgEvidence(HealthKitECGEvidenceFailure)
    case clinicalRecord(HealthKitClinicalRecordFailure)
    /// A source revision classified as an application carries no valid Apple bundle identifier.
    case sourceApplicationInvalid
    /// A repository id was supplied for a node this record's graph does not contain.
    case repositoryIDWithoutNode(ExchangeGraphNode)
    /// A disclosed native identifier system reuses one of the deployment's Grove identity systems.
    case reservedIdentifierSystem
    case exchangeIdentity(ExchangeIdentityError)
    case opaqueIdentity(OpaqueIdentityError)
    case exchangeGraph(ExchangeGraphError)
    case dependency(HealthKitDependencyFailure)

    /// The registered diagnostic; a refusal the registry does not name reports `mobile-input.unclassified`.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .exchangeGraph(let error):
            return error.diagnostic
        case .exchangeIdentity(let error):
            return error.diagnostic
        case .opaqueIdentity(let error):
            return error.diagnostic
        default:
            return rule.diagnostic(at: location)
        }
    }

    private var rule: ExchangeGraphRule {
        switch self {
        case .unregisteredSourceType, .unsupportedSourceType: .mobileInputUnsupportedSourceType
        case .intentionallyUnsupported: .mobileInputIntentionallyUnsupportedSourceType
        case .notYetConvertible: .mobileInputNotYetConvertible
        case .platformExclusiveSourceType: .mobileInputPlatformExclusiveSourceType
        case .componentRequiresCorrelation: .healthkitInputComponentRequiresCorrelation
        case .invalidValue(_, let failure): failure.rule
        case .ecgEvidence: .healthkitInputEcgEvidence
        case .clinicalRecord(let failure): failure.rule
        case .sourceApplicationInvalid: .healthkitInputSourceApplicationInvalid
        case .repositoryIDWithoutNode, .reservedIdentifierSystem, .exchangeIdentity, .opaqueIdentity, .dependency:
            .mobileInputUnclassified
        case .exchangeGraph(let error): ExchangeGraphRule(rawValue: error.diagnostic.code) ?? .mobileExchangeUnclassified
        }
    }

    private var location: String {
        switch self {
        case .unregisteredSourceType, .unsupportedSourceType, .intentionallyUnsupported, .notYetConvertible,
             .platformExclusiveSourceType, .componentRequiresCorrelation:
            "HKSample.sampleType"
        case .invalidValue(_, let failure): failure.location
        case .ecgEvidence: "HKElectrocardiogram"
        case .clinicalRecord: "HKClinicalRecord.fhirResource"
        case .sourceApplicationInvalid: "HKSourceRevision.source.bundleIdentifier"
        case .repositoryIDWithoutNode, .reservedIdentifierSystem: "HealthKitConversionContext"
        case .exchangeIdentity, .opaqueIdentity, .exchangeGraph, .dependency: "Bundle"
        }
    }
}


extension HealthKitValueFailure {
    var rule: ExchangeGraphRule {
        switch self {
        case .shapeInvalid, .invalidMetadataValue, .missingNormativeCode: .mobileInputValueShapeInvalid
        case .outsideDomain: .mobileInputValueOutsideDomain
        case .unsupportedValue, .unsupportedMetadataValue: .mobileInputUnsupportedSourceValue
        case .requiredMetadataMissing: .mobileInputRequiredMetadataMissing
        case .requiredComponentMissing: .mobileInputRequiredComponentMissing
        case .effectivePeriodInvalid: .mobileInputEffectivePeriodInvalid
        case .emptyRecordingSeries: .mobileInputEmptyRecordingSeries
        case .recordingPayloadTooLarge: .mobileInputRecordingPayloadTooLarge
        }
    }

    var location: String {
        switch self {
        case .shapeInvalid, .outsideDomain, .unsupportedValue, .missingNormativeCode: "HKSample.value"
        case .unsupportedMetadataValue(let field), .invalidMetadataValue(let field), .requiredMetadataMissing(let field):
            "HKSample.metadata[\(field.key)]"
        case .requiredComponentMissing(let component): "HKCorrelation.objects[\(component)]"
        case .effectivePeriodInvalid: "HKSample.startDate"
        case .emptyRecordingSeries, .recordingPayloadTooLarge: "HKSample"
        }
    }
}


extension HealthKitClinicalRecordFailure {
    var rule: ExchangeGraphRule {
        switch self {
        case .empty: .healthkitInputClinicalRecordEmpty
        case .undecodable: .mobileInputValueShapeInvalid
        case .unsupportedRelease: .healthkitInputClinicalReleaseUnsupported
        case .unreadableAttachment: .mobileInputUnclassified
        }
    }
}


extension HealthKitConversionError {
    /// Narrows any failure raised while converting one record to this published domain.
    init(conversionFailure error: any Error, source: HealthKitSourceType?) {
        switch error {
        case let error as HealthKitConversionError:
            self = error
        case let failure as HealthKitValueFailure:
            self = source.map { .invalidValue($0, failure) } ?? .dependency(HealthKitDependencyFailure(underlying: failure))
        case let error as ExchangeIdentityError:
            self = .exchangeIdentity(error)
        case let error as OpaqueIdentityError:
            self = .opaqueIdentity(error)
        case let error as ExchangeGraphError:
            self = .exchangeGraph(error)
        default:
            self = .dependency(HealthKitDependencyFailure(underlying: error))
        }
    }
}

#endif
