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


/// A fail-closed refusal of one HealthKit record by ``HealthKitFHIRExporter``; every case reports one registry code.
///
/// A record with several faults is refused for the first in this order, whatever the options: its source type, then
/// whether the export call named it before with other content, then its content (values, units, effective times),
/// then what it states about its origin (its recording device, its writer, its sync identifier and version). A content
/// fault thus reads the same under every writer policy.
public enum HealthKitConversionError: Error, Equatable, Sendable {
    /// The identifier is not in the adapter inventory at all.
    case unregisteredSourceType(String)
    case unsupportedSourceType(HealthKitSourceType)
    case intentionallyUnsupported(HealthKitSourceType, reason: String)
    case notYetConvertible(HealthKitSourceType)
    /// Admitted only as a platform-exclusive recording document, which a bare sample of the type does not carry.
    case platformExclusiveSourceType(HealthKitSourceType)
    /// A blood pressure component converts only inside its admitting correlation.
    case componentRequiresCorrelation(HealthKitSourceType)
    case invalidValue(HealthKitSourceType, ValueFailure)
    case ecgEvidence(ECGEvidenceFailure)
    case clinicalRecord(ClinicalRecordFailure)
    /// A source revision classified as an application carries no valid Apple bundle identifier.
    case sourceApplicationInvalid
    /// The export call named the record, or an ECG's symptom, earlier with other content: other companion data, or
    /// other answers from a policy closure. The first input keeps the record's event; each later one that differs is
    /// refused, so an exact retry of the call reproduces every event.
    case conflictingDuplicate
    case exchangeIdentity(ExchangeIdentityError)
    case exchangeGraph(ExchangeGraphError)
    /// A failure raised by something this domain does not model, named by its type alone: a failing FHIR date
    /// conversion describes itself with the exact instant it could not convert, and that instant identifies a
    /// participant.
    case dependency(String)

    /// The registered diagnostic; a refusal the registry does not name reports `mobile-input.unclassified`.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .exchangeGraph(let error):
            return error.diagnostic
        case .exchangeIdentity(let error):
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
        case .conflictingDuplicate, .exchangeIdentity, .dependency:
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
        case .conflictingDuplicate: "HKSample"
        case .exchangeIdentity, .exchangeGraph, .dependency: "Bundle"
        }
    }
}


extension HealthKitConversionError {
    /// A fail-closed reason why caller-supplied HealthKit ECG evidence was rejected.
    public enum ECGEvidenceFailure: Hashable, Sendable {
        /// An ECG was exported as a bare sample; its voltages and symptoms travel in its
        /// ``HealthKitFHIRExporter/Record/electrocardiogram(_:voltages:symptoms:)`` record.
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
        case unsupportedAlgorithmVersion(Int)
    }

    /// A HealthKit metadata key the adapter reads.
    public enum MetadataField: Hashable, Sendable, CaseIterable {
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
    public enum ValueFailure: Error, Hashable, Sendable {
        /// The value's shape is not what the selected mapping requires.
        case shapeInvalid
        /// A numeric value is nonfinite, outside the contract's inclusive value domain, or fractional where only
        /// integers are admitted.
        case outsideDomain
        /// An enumeration value with no published mapping.
        case unsupportedValue(Int)
        case unsupportedMetadataValue(MetadataField)
        case invalidMetadataValue(MetadataField)
        case requiredMetadataMissing(MetadataField)
        /// A panel is missing one of its catalog components, named by the component id.
        case requiredComponentMissing(component: String)
        /// The effective time is not a valid FHIR date-time, or its period is reversed, or empty where the
        /// measurement requires a duration.
        case effectivePeriodInvalid
        case emptyRecordingSeries
        case recordingPayloadTooLarge(byteCount: Int)
        /// The selected contract states no normative code for the value.
        case missingNormativeCode
    }

    /// Why a clinical record or CDA document could not be carried.
    public enum ClinicalRecordFailure: Hashable, Sendable {
        /// No resource or document bytes, which a query that excludes document data returns.
        case empty
        /// The payload is not one FHIR JSON resource envelope.
        case undecodable
        /// A FHIR release other than DSTU2 or R4.
        case unsupportedRelease
    }
}


extension HealthKitConversionError.ValueFailure {
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


extension HealthKitConversionError.ClinicalRecordFailure {
    var rule: ExchangeGraphRule {
        switch self {
        case .empty: .healthkitInputClinicalRecordEmpty
        case .undecodable: .mobileInputValueShapeInvalid
        case .unsupportedRelease: .healthkitInputClinicalReleaseUnsupported
        }
    }
}


extension HealthKitConversionError {
    /// Narrows any failure raised while converting one record to this published domain.
    init(conversionFailure error: any Error, source: HealthKitSourceType?) {
        switch error {
        case let error as HealthKitConversionError:
            self = error
        case let failure as ValueFailure:
            self = source.map { .invalidValue($0, failure) } ?? Self(dependency: failure)
        case let error as ExchangeIdentityError:
            self = .exchangeIdentity(error)
        case let error as ExchangeGraphError:
            self = .exchangeGraph(error)
        default:
            self = Self(dependency: error)
        }
    }

    /// Narrows a failure to build a deleted record's retraction event to this published domain; the event's own checks,
    /// such as a deletion bound no FHIR dateTime can state, are refused as a dependency. (The exporter already refuses a
    /// reserved native identifier system when it is configured.)
    init(_ error: RetractionEvent.ValidationError) {
        self = switch error {
        case .exchangeIdentity(let error): .exchangeIdentity(error)
        case .exchangeGraph(let error): .exchangeGraph(error)
        case .emptyTargets, .duplicateTarget, .invalidSourceRecord, .reservedIdentifierSystem, .invalidInstant, .invalidOccurrencePeriod:
            Self(dependency: error)
        }
    }

    /// A ``dependency(_:)`` refusal naming the type of `error`, never its description.
    init(dependency error: any Error) {
        self = .dependency(String(reflecting: type(of: error)))
    }
}

#endif
