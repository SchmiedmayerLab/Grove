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

    public var diagnostic: ExchangeGraphDiagnostic {
        let (rule, location): (ExchangeGraphRule, String) = switch self {
        case .measurementUnknown, .measurementNotMappable: (.mobileInputUnsupportedSourceType, "Observation.code")
        case .unitNotMappable: (.mobileOutputFixedQuantityUnit, "Observation.valueQuantity.code")
        case .valueMissing: (.mobileInputValueShapeInvalid, "Observation.value")
        case .componentMissing: (.mobileInputRequiredComponentMissing, "Observation.component")
        case .effectiveMissing: (.mobileInputEffectivePeriodInvalid, "Observation.effective")
        }
        return ExchangeGraphDiagnostic(code: rule.rawValue, reason: rule.reason, location: location, severity: rule.severity)
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

    /// Every measurement bound to exactly one HealthKit quantity type, inverted from the
    /// forward catalog bindings so the two directions cannot drift apart.
    private static let quantityTypesByMeasurementID: [String: HKQuantityTypeIdentifier] = {
        var candidates: [String: [HKQuantityTypeIdentifier]] = [:]
        for identifier in HKQuantityTypeIdentifier.allKnownIdentifiers {
            guard case .quantity(let contract, _)? = HealthKitCatalog.quantityBinding(for: identifier.rawValue) else {
                continue
            }
            candidates[contract.id, default: []].append(identifier)
        }
        return candidates.compactMapValues { identifiers in
            identifiers.count == 1 ? identifiers[0] : nil
        }
    }()

    static func contract(
        for observation: ModelsR4.Observation
    ) throws(HealthKitSampleProjectionError) -> HealthKitFHIRObservationContract {
        let coding = observation.code.coding?.first
        let system = coding?.system?.value?.url.absoluteString ?? ""
        let code = coding?.code?.value?.string ?? ""
        let shared = (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).first {
            $0.code.system == system && $0.code.code == code
        }
        guard let shared else {
            throw HealthKitSampleProjectionError.measurementUnknown(system: system, code: code)
        }
        return HealthKitFHIRObservationContract(shared: shared)
    }

    static func quantityTypeIdentifier(
        for measurementID: String
    ) throws(HealthKitSampleProjectionError) -> HKQuantityTypeIdentifier {
        guard let identifier = quantityTypesByMeasurementID[measurementID] else {
            throw HealthKitSampleProjectionError.measurementNotMappable(id: measurementID)
        }
        return identifier
    }

    static func envelope(
        of observation: ModelsR4.Observation,
        contract: HealthKitFHIRObservationContract,
        syncIdentifier: String?
    ) throws(HealthKitSampleProjectionError) -> SampleEnvelope {
        guard case .dateTime(let effective)? = observation.effective,
              let dateTime = effective.value,
              let date = try? dateTime.asNSDate() else {
            throw HealthKitSampleProjectionError.effectiveMissing(id: contract.id)
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

    static func bloodPressureCorrelation(
        for observation: ModelsR4.Observation,
        contract: HealthKitFHIRObservationContract,
        envelope: SampleEnvelope
    ) throws(HealthKitSampleProjectionError) -> HKCorrelation {
        func member(
            _ componentID: String,
            _ type: HKQuantityTypeIdentifier
        ) throws(HealthKitSampleProjectionError) -> HKQuantitySample {
            guard let declared = contract.components.first(where: { $0.id == componentID }) else {
                throw HealthKitSampleProjectionError.componentMissing(id: contract.id, code: componentID)
            }
            let component = observation.component?.first {
                $0.code.coding?.contains { coding in
                    coding.system?.value?.url.absoluteString == declared.system
                        && coding.code?.value?.string == declared.code
                } ?? false
            }
            guard let component, case .quantity(let quantity) = component.value else {
                throw HealthKitSampleProjectionError.componentMissing(id: contract.id, code: declared.code)
            }
            return HKQuantitySample(
                type: HKQuantityType(type),
                quantity: try healthKitQuantity(quantity, contract: declared.quantity, measurementID: contract.id),
                start: envelope.date,
                end: envelope.date
            )
        }
        let systolic = try member("systolic", .bloodPressureSystolic)
        let diastolic = try member("diastolic", .bloodPressureDiastolic)
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: envelope.date,
            end: envelope.date,
            objects: [systolic, diastolic],
            metadata: envelope.metadata
        )
    }

    /// The value under the unit its measurement contract fixes.
    ///
    /// The stated system and code are checked against the contract rather than looked up: a code
    /// from another dimension would otherwise mint an HKQuantity that `HKQuantitySample` rejects
    /// with an uncatchable exception.
    static func healthKitQuantity(
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
    /// This is the reverse of the converter's observation assembly, derived from the same catalog
    /// bindings: the code selects the measurement contract, the contract selects the one HealthKit
    /// quantity type bound to it, and the published unit bindings read the value's UCUM unit.
    /// A measurement bound to several HealthKit types, or to none, refuses rather than guessing.
    ///
    /// A manual-entry recording method becomes `HKMetadataKeyWasUserEntered`, the effective
    /// instant's zone `HKMetadataKeyTimeZone`, and the minted source-output identity
    /// `HKMetadataKeySyncIdentifier`, so a reading re-projected from any exchange graph replaces
    /// the earlier sample instead of duplicating it.
    ///
    /// - Parameter syncIdentifier: A stable per-reading discriminator in place of the source-output identity.
    public func healthKitSample(syncIdentifier: String? = nil) throws(HealthKitSampleProjectionError) -> HKSample {
        let contract = try HealthKitSampleProjection.contract(for: self)
        let envelope = try HealthKitSampleProjection.envelope(of: self, contract: contract, syncIdentifier: syncIdentifier)
        if contract.code.code == MeasurementCatalog.bloodPressure.code.code {
            return try HealthKitSampleProjection.bloodPressureCorrelation(for: self, contract: contract, envelope: envelope)
        }
        guard case .quantity(let quantity)? = value else {
            throw HealthKitSampleProjectionError.valueMissing(id: contract.id)
        }
        return HKQuantitySample(
            type: HKQuantityType(try HealthKitSampleProjection.quantityTypeIdentifier(for: contract.id)),
            quantity: try HealthKitSampleProjection.healthKitQuantity(quantity, contract: contract.quantity, measurementID: contract.id),
            start: envelope.date,
            end: envelope.date,
            metadata: envelope.metadata
        )
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
