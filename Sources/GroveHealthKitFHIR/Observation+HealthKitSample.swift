//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The projection reads top-down from the entry point through measurement, envelope and values.

#if canImport(HealthKit)

import Foundation
public import GroveFHIRContract
public import HealthKit
public import ModelsR4


/// Why a Grove observation cannot become a HealthKit sample; every case reports one registry code.
public enum HealthKitSampleProjectionError: Error, Equatable, Sendable {
    /// The observation's code names no Grove measurement.
    case measurementUnknown(system: String, code: String)
    /// The measurement has no single HealthKit quantity type the projection can write: none or several are bound, the
    /// observation's HealthKit lineage names another source type, or HealthKit requires source metadata the projection
    /// does not restore.
    case measurementNotMappable(id: String)
    case unitNotMappable(code: String)
    case valueMissing(id: String)
    case componentMissing(id: String, code: String)
    /// The observation states no effective, or its instant does not parse.
    case effectiveMissing(id: String)
    /// The effective has a datatype the measurement's profile does not admit: a Period on an instant-only
    /// measurement, an instant on a Period-only one, or an instant or Timing anywhere.
    case effectiveTypeNotAdmitted(id: String)
    /// The effective Period cannot be a HealthKit sample's interval: it lacks a start or an end, an endpoint does not
    /// parse, it ends before it starts, it has zero width where the measurement requires a non-zero Period, or its
    /// duration is outside what HealthKit allows for the sample type.
    case effectivePeriodInvalid(id: String)

    public var diagnostic: ProducerDiagnostic {
        let (rule, location): (ExchangeGraphRule, String) = switch self {
        case .measurementUnknown, .measurementNotMappable: (.mobileInputUnsupportedSourceType, "Observation.code")
        case .unitNotMappable: (.mobileOutputFixedQuantityUnit, "Observation.valueQuantity.code")
        case .valueMissing: (.mobileInputValueShapeInvalid, "Observation.value")
        case .componentMissing: (.mobileInputRequiredComponentMissing, "Observation.component")
        case .effectiveMissing: (.mobileInputEffectivePeriodInvalid, "Observation.effective")
        case .effectiveTypeNotAdmitted: (.mobileInputEffectivePeriodInvalid, "Observation.effective[x]")
        case .effectivePeriodInvalid: (.mobileInputEffectivePeriodInvalid, "Observation.effectivePeriod")
        }
        return ProducerDiagnostic(code: rule.rawValue, reason: rule.reason, location: location, severity: rule.severity)
    }
}


/// One entry of a graph that could not be projected back into a sample.
public struct HealthKitSampleProjectionFailure: Error, Sendable {
    public let fullURL: FHIRPrimitive<FHIRURI>
    public let error: HealthKitSampleProjectionError
}


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitSampleProjection {
    /// The interval and metadata every projected sample shares.
    struct SampleEnvelope {
        let start: Date
        let end: Date
        let metadata: [String: Any]
    }

    /// When an observation's effective says its sample happened, and the zone of the start's offset.
    private struct SampleInterval {
        let start: Date
        let end: Date
        let zone: TimeZone?
    }

    /// The system and code of the coding that names a measurement.
    struct MeasurementCode: Hashable {
        /// The code system.
        let system: String
        /// The code.
        let code: String
    }

    /// Every generated measurement by its code's system and code, the first catalog stating one winning. Body-mass
    /// index, which no catalog lists, is unknown.
    static let measurements: [MeasurementCode: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { (MeasurementCode(system: $0.code.system, code: $0.code.code), $0) }
    ) { first, _ in first }

    /// The quantity type each measurement lands on: the one quantity type whose plan reads the measurement in its
    /// contract's unit. A measurement several types read, or none, has none, so it refuses rather than guessing; so
    /// does one whose plan requires metadata the projection does not restore (an insulin delivery's reason), as
    /// HealthKit raises on such a sample without it.
    static let quantityTypes: [String: HKQuantityTypeIdentifier] = {
        let readers = HealthKitContentPlan.all.compactMap { plan -> (String, [HealthKitContentPlan])? in
            guard plan.unitBinding != nil, plan.sourceType.rawValue.hasPrefix("HKQuantityTypeIdentifier"),
                  let measurement = plan.entry.measurements.first else {
                return nil
            }
            return (measurement.id, [plan])
        }
        return Dictionary(readers, uniquingKeysWith: +).compactMapValues { plans in
            guard plans.count == 1, !requiresMetadata(plans[0]) else {
                return nil
            }
            return HKQuantityTypeIdentifier(rawValue: plans[0].sourceType.rawValue)
        }
    }()

    /// The one sample `observation` describes, read from the content plans: its code names the measurement, the
    /// measurement the quantity type whose plan reads it, and the published unit bindings the value's unit; a
    /// blood-pressure panel becomes a correlation of its members.
    static func sample(of observation: ModelsR4.Observation, syncIdentifier: String?) throws(HealthKitSampleProjectionError) -> HKSample {
        let coding = observation.code.coding?.first
        let system = coding?.system?.value?.url.absoluteString ?? ""
        let code = coding?.code?.value?.string ?? ""
        guard let contract = measurements[MeasurementCode(system: system, code: code)] else {
            throw .measurementUnknown(system: system, code: code)
        }
        if contract.code.code == MeasurementCatalog.bloodPressure.code.code {
            let type = HKCorrelationType(.bloodPressure)
            let envelope = try envelope(of: observation, contract: contract, sampleType: type, syncIdentifier: syncIdentifier)
            return try correlation(of: observation, contract: contract, envelope: envelope)
        }
        let type = HKQuantityType(try quantityType(of: observation, contract: contract))
        let envelope = try envelope(of: observation, contract: contract, sampleType: type, syncIdentifier: syncIdentifier)
        guard case .quantity(let quantity)? = observation.value else {
            throw .valueMissing(id: contract.id)
        }
        return HKQuantitySample(
            type: type,
            quantity: try healthKitQuantity(quantity, contract: contract.quantity, measurementID: contract.id),
            start: envelope.start,
            end: envelope.end,
            metadata: envelope.metadata
        )
    }

    /// The quantity type `observation` lands on: its measurement's, unless the observation's HealthKit lineage names
    /// another source type, as an ECG's average heart rate does. An observation without lineage keeps its
    /// measurement's.
    private static func quantityType(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> HKQuantityTypeIdentifier {
        guard let identifier = quantityTypes[contract.id],
              sourceTypeLineage(of: observation).map({ $0 == identifier.rawValue }) ?? true else {
            throw .measurementNotMappable(id: contract.id)
        }
        return identifier
    }

    /// Whether a plan requires a metadata value the projection does not restore.
    private static func requiresMetadata(_ plan: HealthKitContentPlan) -> Bool {
        guard case .observation(let content) = plan.route, let component = content.metadataComponent else {
            return false
        }
        return component.reading != .optionalInteger
    }

    /// The correlation a blood-pressure panel describes: one member per correlation member the content rules state,
    /// in their order, each from the panel's component the contract codes it as.
    private static func correlation(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract,
        envelope: SampleEnvelope
    ) throws(HealthKitSampleProjectionError) -> HKCorrelation {
        let members = try HealthKitContentRules.bloodPressureMembers.map { id, type throws(HealthKitSampleProjectionError) -> HKSample in
            guard let declared = contract.components.first(where: { $0.id == id }) else {
                throw .componentMissing(id: contract.id, code: id)
            }
            let stated = observation.component?.first { component in
                component.code.coding?.contains { coding in
                    coding.system?.value?.url.absoluteString == declared.system && coding.code?.value?.string == declared.code
                } ?? false
            }
            guard let stated, case .quantity(let quantity) = stated.value else {
                throw .componentMissing(id: contract.id, code: declared.code)
            }
            return HKQuantitySample(
                type: HKQuantityType(HKQuantityTypeIdentifier(rawValue: type.rawValue)),
                quantity: try healthKitQuantity(quantity, contract: declared.quantity, measurementID: contract.id),
                start: envelope.start,
                end: envelope.end
            )
        }
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: envelope.start,
            end: envelope.end,
            objects: Set(members),
            metadata: envelope.metadata
        )
    }

    /// The interval and metadata the observation states: its effective interval (in the proleptic Gregorian calendar,
    /// as the converter states it) and zone, within the duration HealthKit allows for `sampleType`, manual entry, and
    /// the sync identifier and version a re-projected reading replaces its earlier sample by.
    private static func envelope(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract,
        sampleType: HKSampleType,
        syncIdentifier: String?
    ) throws(HealthKitSampleProjectionError) -> SampleEnvelope {
        let interval = try interval(of: observation, contract: contract)
        let duration = interval.end.timeIntervalSince(interval.start)
        // The allowed-duration getters raise for a type without that restriction, so the flags are read first.
        guard !(sampleType.isMinimumDurationRestricted && duration < sampleType.minimumAllowedDuration),
              !(sampleType.isMaximumDurationRestricted && duration > sampleType.maximumAllowedDuration) else {
            throw .effectivePeriodInvalid(id: contract.id)
        }
        var metadata: [String: Any] = [:]
        if let zone = interval.zone {
            metadata[HKMetadataKeyTimeZone] = zone.identifier
        }
        if isManualEntry(observation) {
            metadata[HKMetadataKeyWasUserEntered] = true
        }
        if let syncIdentifier = syncIdentifier ?? sourceOutputIdentity(of: observation) {
            metadata[HKMetadataKeySyncIdentifier] = syncIdentifier
            metadata[HKMetadataKeySyncVersion] = writerRecordVersion(of: observation)
                ?? (observation.status.value == .amended ? 2 : 1)
        }
        return SampleEnvelope(start: interval.start, end: interval.end, metadata: metadata)
    }

    /// The interval the observation's effective states where the measurement's profile admits its datatype: an
    /// instant as a zero-width interval, a Period as its endpoints when they are an interval the profile admits.
    /// HealthKit needs an end, so an open Period refuses rather than guessing one.
    private static func interval(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> SampleInterval {
        let rule = EffectiveRule(contract)
        switch observation.effective {
        case nil:
            throw .effectiveMissing(id: contract.id)
        case .dateTime(let effective) where rule == .instant:
            guard let instant = instant(effective) else {
                throw .effectiveMissing(id: contract.id)
            }
            return SampleInterval(start: instant.date, end: instant.date, zone: instant.zone)
        case .period(let period) where rule != .instant:
            // A pair reversed by less than a millisecond can round to one wire millisecond; HealthKit raises on it.
            guard let start = instant(period.start), let end = instant(period.end), start.date <= end.date,
                  (try? rule.admitsPeriod(from: start.date, to: end.date)) == true else {
                throw .effectivePeriodInvalid(id: contract.id)
            }
            return SampleInterval(start: start.date, end: end.date, zone: start.zone)
        default:
            throw .effectiveTypeNotAdmitted(id: contract.id)
        }
    }

    /// The instant a date-time states and the zone of its offset, or `nil` when it states none or one HealthKit cannot
    /// hold: from `Date.distantFuture` (4001-01-01T00:00:00Z) on, `HKSample` raises an uncatchable exception.
    private static func instant(_ dateTime: FHIRPrimitive<DateTime>?) -> (date: Date, zone: TimeZone?)? {
        guard let value = dateTime?.value, let date = HealthKitEffectiveTime.instant(of: value), date < .distantFuture else {
            return nil
        }
        return (date, value.timeZone)
    }

    /// The source type the observation's `healthkit-source-type` extension names, if it states one.
    private static func sourceTypeLineage(of observation: ModelsR4.Observation) -> String? {
        let marker = observation.extension?.first { $0.url == Canonicals.healthKitSourceTypeExtension }
        guard case .code(let code)? = marker?.value else {
            return nil
        }
        return code.value?.string
    }

    private static func writerRecordVersion(of observation: ModelsR4.Observation) -> Int? {
        let marker = observation.extension?.first { $0.url == Canonicals.writerRecordVersion }
        guard case .string(let value)? = marker?.value,
              let version = value.value?.string else {
            return nil
        }
        return Int(version)
    }

    private static func sourceOutputIdentity(of observation: ModelsR4.Observation) -> String? {
        observation.identifier?.first { identifier in
            identifier.type?.coding?.contains {
                $0.system == Canonicals.identifierRoleCodeSystem
                    && $0.code?.value?.string == GroveIdentifierRole.sourceOutput.rawValue
            } == true
        }?.value?.value?.string
    }

    private static func isManualEntry(_ observation: ModelsR4.Observation) -> Bool {
        let url = Canonicals.recordingMethod.value?.url.absoluteString
        return observation.extension?.contains { marker in
            guard marker.url.value?.url.absoluteString == url,
                  case .coding(let coding)? = marker.value else {
                return false
            }
            return coding.code?.value?.string == "manual-entry"
        } ?? false
    }

    /// The value under the unit its measurement contract fixes.
    ///
    /// The stated system and code are checked against the contract rather than looked up: a code
    /// from another dimension would otherwise mint an HKQuantity that `HKQuantitySample` rejects
    /// with an uncatchable exception.
    private static func healthKitQuantity(
        _ quantity: Quantity,
        contract: QuantityContract?,
        measurementID: String
    ) throws(HealthKitSampleProjectionError) -> HKQuantity {
        guard let decimal = quantity.value?.value?.decimal else {
            throw HealthKitSampleProjectionError.valueMissing(id: measurementID)
        }
        let code = quantity.code?.value?.string ?? ""
        guard let contract,
              quantity.system?.value?.url.absoluteString == contract.system,
              code == contract.code,
              let unit = HealthKitCatalog.unit(forUCUMCode: contract.code) else {
            throw HealthKitSampleProjectionError.unitNotMappable(code: code)
        }
        return HKQuantity(unit: unit, doubleValue: NSDecimalNumber(decimal: decimal).doubleValue)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Observation {
    /// The one sample this observation describes.
    ///
    /// This is the reverse of the exporter's observation assembly, derived from the same content
    /// plans: the code selects the measurement contract, the contract selects the one HealthKit
    /// quantity type whose plan reads it, and the published unit bindings read the value's UCUM unit.
    /// A measurement read by several HealthKit types, or by none, refuses rather than guessing, and so
    /// does an observation whose HealthKit lineage names another source type.
    ///
    /// An `effectiveDateTime` becomes an instant sample and an `effectivePeriod` the sample's start and
    /// end, each only where the measurement's profile admits that datatype and within the duration
    /// HealthKit allows for the type; anything else refuses with a typed error.
    ///
    /// The effective time is read in the proleptic Gregorian calendar the converter states it in,
    /// so a reading from before the 1582 calendar reform lands on its own instant. An instant
    /// HealthKit cannot hold, from 4001-01-01T00:00:00Z (`Date.distantFuture`) on, refuses with
    /// ``HealthKitSampleProjectionError/effectiveMissing(id:)``, and a Period bound there with
    /// ``HealthKitSampleProjectionError/effectivePeriodInvalid(id:)``.
    ///
    /// A manual-entry recording method becomes `HKMetadataKeyWasUserEntered`, the effective
    /// start's zone `HKMetadataKeyTimeZone`, and the minted source-output identity
    /// `HKMetadataKeySyncIdentifier`, so a reading re-projected from any exchange graph replaces
    /// the earlier sample instead of duplicating it.
    ///
    /// - Parameter syncIdentifier: A stable per-reading discriminator in place of the source-output identity.
    public func healthKitSample(syncIdentifier: String? = nil) throws(HealthKitSampleProjectionError) -> HKSample {
        try HealthKitSampleProjection.sample(of: self, syncIdentifier: syncIdentifier)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeGraph {
    /// Every Observation of the graph as the sample it describes, with a typed failure for each that refuses.
    public func healthKitSamples() -> ConversionBatch<HKSample, HealthKitSampleProjectionFailure> {
        var samples: [HKSample] = []
        var failures: [HealthKitSampleProjectionFailure] = []
        for entry in bundle.entry ?? [] {
            guard case .observation(let observation)? = entry.resource, let fullURL = entry.fullUrl else {
                continue
            }
            do {
                samples.append(try observation.healthKitSample())
            } catch {
                failures.append(HealthKitSampleProjectionFailure(fullURL: fullURL, error: error))
            }
        }
        return ConversionBatch(conversions: samples, failures: failures)
    }
}

#endif
