//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
public import HealthKit
public import ModelsR4


/// Why a Grove observation cannot become a HealthKit sample.
public enum HealthKitSampleProjectionError: Error, Equatable {
    /// The observation's code names no Grove measurement.
    case measurementUnknown(system: String, code: String)
    /// The measurement has no unambiguous HealthKit quantity type to land on.
    case measurementNotMappable(id: String)
    case unitNotMappable(code: String)
    case valueMissing(id: String)
    case componentMissing(id: String, code: String)
    case effectiveMissing(id: String)
}


/// Projects a Grove observation back into the HealthKit sample it describes.
///
/// This is the reverse of the converter's observation assembly, derived from the same catalog
/// bindings: the observation's code selects the measurement contract, the contract selects the
/// one HealthKit quantity type bound to it, and the published unit bindings read the value's
/// UCUM unit.
/// A measurement bound to several HealthKit types -- or to none -- refuses rather than guessing,
/// exactly as the forward direction refuses source types it does not model.
///
/// The sample carries what the observation states beyond its value: a manual-entry recording
/// method becomes `HKMetadataKeyWasUserEntered`, the effective instant's zone becomes
/// `HKMetadataKeyTimeZone`, and the observation's minted source-output identity becomes
/// `HKMetadataKeySyncIdentifier` with the sync version taken from the observation's status --
/// an amended observation replaces the final one it corrects. An observation taken from a
/// Grove exchange bundle therefore syncs under the same deterministic identity the exchange
/// dedups on; one from elsewhere can pass an explicit identifier instead.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum HealthKitSampleProjection {
    /// The instant and metadata every projected sample shares.
    private struct SampleEnvelope {
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

    /// The one sample the observation describes.
    ///
    /// - Parameters:
    ///   - observation: A Grove observation whose code names a catalog measurement.
    ///   - syncIdentifier: A stable per-reading discriminator. When nil, the observation's
    ///     own source-output identity is used, so a reading re-projected from any exchange
    ///     bundle replaces the earlier sample instead of duplicating it.
    public static func sample(
        for observation: ModelsR4.Observation,
        syncIdentifier: String? = nil
    ) throws -> HKSample {
        let contract = try contract(for: observation)
        let envelope = try envelope(of: observation, contract: contract, syncIdentifier: syncIdentifier)
        if contract.code.code == MeasurementCatalog.bloodPressure.code.code {
            return try bloodPressureCorrelation(for: observation, contract: contract, envelope: envelope)
        }
        guard case .quantity(let quantity)? = observation.value else {
            throw HealthKitSampleProjectionError.valueMissing(id: contract.id)
        }
        return HKQuantitySample(
            type: HKQuantityType(try quantityTypeIdentifier(for: contract.id)),
            quantity: try healthKitQuantity(quantity, measurementID: contract.id),
            start: envelope.date,
            end: envelope.date,
            metadata: envelope.metadata
        )
    }

    // MARK: Measurement Resolution

    private static func contract(
        for observation: ModelsR4.Observation
    ) throws -> HealthKitFHIRObservationContract {
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

    private static func quantityTypeIdentifier(for measurementID: String) throws -> HKQuantityTypeIdentifier {
        guard let identifier = quantityTypesByMeasurementID[measurementID] else {
            throw HealthKitSampleProjectionError.measurementNotMappable(id: measurementID)
        }
        return identifier
    }

    // MARK: Sample Envelope

    private static func envelope(
        of observation: ModelsR4.Observation,
        contract: HealthKitFHIRObservationContract,
        syncIdentifier: String?
    ) throws -> SampleEnvelope {
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
            metadata[HKMetadataKeySyncVersion] = observation.status.value == .amended ? 2 : 1
        }
        return SampleEnvelope(date: date, metadata: metadata)
    }

    private static func sourceOutputIdentity(of observation: ModelsR4.Observation) -> String? {
        let roleSystem = Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
        let identifier = observation.identifier?.first { identifier in
            identifier.type?.coding?.contains { coding in
                coding.system?.value?.url.absoluteString == roleSystem
                    && coding.code?.value?.string == "source-output"
            } ?? false
        }
        return identifier?.value?.value?.string
    }

    private static func isManualEntry(_ observation: ModelsR4.Observation) -> Bool {
        let url = Canonicals.recordingMethod.value?.url.absoluteString
        return observation.extension?.contains { marker in
            guard marker.url.value?.url.absoluteString == url,
                  case .codeableConcept(let concept)? = marker.value else {
                return false
            }
            return concept.coding?.contains { $0.code?.value?.string == "manual-entry" } ?? false
        } ?? false
    }

    // MARK: Values

    private static func bloodPressureCorrelation(
        for observation: ModelsR4.Observation,
        contract: HealthKitFHIRObservationContract,
        envelope: SampleEnvelope
    ) throws -> HKCorrelation {
        func member(_ code: String, _ type: HKQuantityTypeIdentifier) throws -> HKQuantitySample {
            let component = observation.component?.first {
                $0.code.coding?.contains { $0.code?.value?.string == code } ?? false
            }
            guard let component, case .quantity(let quantity) = component.value else {
                throw HealthKitSampleProjectionError.componentMissing(id: contract.id, code: code)
            }
            return HKQuantitySample(
                type: HKQuantityType(type),
                quantity: try healthKitQuantity(quantity, measurementID: contract.id),
                start: envelope.date,
                end: envelope.date
            )
        }
        let systolic = try member("8480-6", .bloodPressureSystolic)
        let diastolic = try member("8462-4", .bloodPressureDiastolic)
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: envelope.date,
            end: envelope.date,
            objects: [systolic, diastolic],
            metadata: envelope.metadata
        )
    }

    private static func healthKitQuantity(_ quantity: Quantity, measurementID: String) throws -> HKQuantity {
        guard let decimal = quantity.value?.value?.decimal else {
            throw HealthKitSampleProjectionError.valueMissing(id: measurementID)
        }
        let code = quantity.code?.value?.string ?? ""
        guard let unit = HealthKitCatalog.unit(forUCUMCode: code) else {
            throw HealthKitSampleProjectionError.unitNotMappable(code: code)
        }
        return HKQuantity(unit: unit, doubleValue: NSDecimalNumber(decimal: decimal).doubleValue)
    }
}

#endif
