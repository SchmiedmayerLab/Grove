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
    /// The measurement has no unambiguous HealthKit quantity type to land on.
    case measurementNotMappable(id: String)
    case unitNotMappable(code: String)
    case valueMissing(id: String)
    case componentMissing(id: String, code: String)
    case effectiveMissing(id: String)

    public var diagnostic: ProducerDiagnostic {
        let (rule, location): (ExchangeGraphRule, String) = switch self {
        case .measurementUnknown, .measurementNotMappable: (.mobileInputUnsupportedSourceType, "Observation.code")
        case .unitNotMappable: (.mobileOutputFixedQuantityUnit, "Observation.valueQuantity.code")
        case .valueMissing: (.mobileInputValueShapeInvalid, "Observation.value")
        case .componentMissing: (.mobileInputRequiredComponentMissing, "Observation.component")
        case .effectiveMissing: (.mobileInputEffectivePeriodInvalid, "Observation.effective")
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
    /// The instant and metadata every projected sample shares.
    struct SampleEnvelope {
        let date: Date
        let metadata: [String: Any]
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
    /// contract's unit. A measurement several types read, or none, has none, so it refuses rather than guessing.
    static let quantityTypes: [String: HKQuantityTypeIdentifier] = {
        let readers = HealthKitContentPlan.all.compactMap { plan -> (String, [HealthKitSourceType])? in
            guard plan.unitBinding != nil, plan.sourceType.rawValue.hasPrefix("HKQuantityTypeIdentifier"),
                  let measurement = plan.entry.measurements.first else {
                return nil
            }
            return (measurement.id, [plan.sourceType])
        }
        return Dictionary(readers, uniquingKeysWith: +).compactMapValues { types in
            types.count == 1 ? HKQuantityTypeIdentifier(rawValue: types[0].rawValue) : nil
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
        let envelope = try envelope(of: observation, measurementID: contract.id, syncIdentifier: syncIdentifier)
        if contract.code.code == MeasurementCatalog.bloodPressure.code.code {
            return try correlation(of: observation, contract: contract, envelope: envelope)
        }
        guard case .quantity(let quantity)? = observation.value else {
            throw .valueMissing(id: contract.id)
        }
        guard let type = quantityTypes[contract.id] else {
            throw .measurementNotMappable(id: contract.id)
        }
        return HKQuantitySample(
            type: HKQuantityType(type),
            quantity: try healthKitQuantity(quantity, contract: contract.quantity, measurementID: contract.id),
            start: envelope.date,
            end: envelope.date,
            metadata: envelope.metadata
        )
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
                start: envelope.date,
                end: envelope.date
            )
        }
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: envelope.date,
            end: envelope.date,
            objects: Set(members),
            metadata: envelope.metadata
        )
    }

    /// The instant and metadata the observation states: its effective instant and zone, manual entry, and the sync
    /// identifier and version a re-projected reading replaces its earlier sample by.
    private static func envelope(
        of observation: ModelsR4.Observation,
        measurementID: String,
        syncIdentifier: String?
    ) throws(HealthKitSampleProjectionError) -> SampleEnvelope {
        guard case .dateTime(let effective)? = observation.effective,
              let dateTime = effective.value,
              let date = try? dateTime.asNSDate() else {
            throw HealthKitSampleProjectionError.effectiveMissing(id: measurementID)
        }
        var metadata: [String: Any] = [:]
        if let zone = dateTime.timeZone {
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
        return SampleEnvelope(date: date, metadata: metadata)
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
    /// This is the reverse of the converter's observation assembly, derived from the same content
    /// plans: the code selects the measurement contract, the contract selects the one HealthKit
    /// quantity type whose plan reads it, and the published unit bindings read the value's UCUM unit.
    /// A measurement read by several HealthKit types, or by none, refuses rather than guessing.
    ///
    /// A manual-entry recording method becomes `HKMetadataKeyWasUserEntered`, the effective
    /// instant's zone `HKMetadataKeyTimeZone`, and the minted source-output identity
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
