//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import GroveFHIRContract
import HealthKit
public import ModelsR4

// The public row/value types precede the catalog that publishes them so generated data stays readable.
// swiftlint:disable file_types_order


/// Implementation state of one HealthKit input in the v0.2 Swift producer.
public typealias HealthKitFHIRImplementationStatus = GroveFHIRHealthKitImplementationStatus


/// One measurement and its exact direct profile claims in the HealthKit adapter matrix.
public struct HealthKitFHIRMeasurementContract: Sendable {
    public let id: String
    public let profiles: [FHIRPrimitive<Canonical>]
}


struct HealthKitFHIRCodingContract: Sendable {
    let system: String
    let code: String
}


struct HealthKitFHIRQuantityContract: Sendable {
    let system: String
    let code: String
}


struct HealthKitFHIRComponentContract: Sendable {
    let id: String
    let system: String
    let code: String
    let quantity: HealthKitFHIRQuantityContract
}


struct HealthKitFHIRObservationContract: Sendable {
    static let bodyMassIndex = HealthKitFHIRObservationContract(
        measurement: HealthKitFHIRMeasurementContract(
            id: "body-mass-index",
            profiles: GroveFHIRHealthKitCatalog.bodyMassIndexProfiles
        ),
        code: HealthKitFHIRCodingContract(system: "http://loinc.org", code: "39156-5"),
        quantity: HealthKitFHIRQuantityContract(
            system: "http://unitsofmeasure.org",
            code: "kg/m2"
        ),
        effective: .dateTime
    )

    let measurement: HealthKitFHIRMeasurementContract
    let code: HealthKitFHIRCodingContract
    let quantity: HealthKitFHIRQuantityContract?
    let components: [HealthKitFHIRComponentContract]
    let resultCodeSystem: String?
    let effective: GroveFHIRMeasurementEffective

    var id: String { measurement.id }
    var profiles: [FHIRPrimitive<Canonical>] { measurement.profiles }

    init(shared: GroveFHIRMeasurementContract) {
        self.measurement = HealthKitFHIRMeasurementContract(
            id: shared.id,
            profiles: GroveFHIRProfileClaims.observation(
                sharedMeasurement: shared.profile,
                adapter: GroveFHIRProfile.healthkitObservation
            )
        )
        self.code = HealthKitFHIRCodingContract(system: shared.code.system, code: shared.code.code)
        self.quantity = shared.quantity.map {
            HealthKitFHIRQuantityContract(system: $0.system, code: $0.code)
        }
        self.components = shared.components.map {
            HealthKitFHIRComponentContract(
                id: $0.id,
                system: $0.system,
                code: $0.code,
                quantity: HealthKitFHIRQuantityContract(
                    system: $0.quantity.system,
                    code: $0.quantity.code
                )
            )
        }
        self.resultCodeSystem = shared.resultCodeSystem
        self.effective = shared.effective
    }

    private init(
        measurement: HealthKitFHIRMeasurementContract,
        code: HealthKitFHIRCodingContract,
        quantity: HealthKitFHIRQuantityContract?,
        components: [HealthKitFHIRComponentContract] = [],
        resultCodeSystem: String? = nil,
        effective: GroveFHIRMeasurementEffective
    ) {
        self.measurement = measurement
        self.code = code
        self.quantity = quantity
        self.components = components
        self.resultCodeSystem = resultCodeSystem
        self.effective = effective
    }
}


/// One authoritative row in the HealthKit-to-v0.2 implementation matrix.
public struct HealthKitFHIRCatalogEntry: Sendable {
    public let sourceTypeIdentifier: String
    public let title: String
    /// The one selected contract, or all candidate contracts when source facts cannot select one.
    public let measurements: [HealthKitFHIRMeasurementContract]
    public let implementationStatus: HealthKitFHIRImplementationStatus
    public let requirement: String?
}


/// Closed, fail-closed catalog used by ``HealthKitFHIRConverter``.
///
/// This catalog alone determines whether the public API may claim a Grove v0.2 profile.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum HealthKitFHIRCatalog {
    /// Every HealthKit sample type known to Grove plus the explicit sleep-duration aggregate.
    /// HealthKit characteristics are not samples and are outside this converter's input type.
    /// A consumer can render this directly as the implementation coverage matrix.
    public static let entries: [HealthKitFHIRCatalogEntry] = GroveFHIRHealthKitCatalog.rows.map { row in
        HealthKitFHIRCatalogEntry(
            sourceTypeIdentifier: row.sourceTypeIdentifier,
            title: row.title,
            measurements: row.measurementIDs.map { id in
                HealthKitFHIRMeasurementContract(id: id, profiles: row.profiles)
            },
            implementationStatus: row.implementationStatus,
            requirement: row.requirement
        )
    }

    static func entry(for sample: HKSample) -> HealthKitFHIRCatalogEntry? {
        entries.first { $0.sourceTypeIdentifier == sample.sampleType.identifier }
    }

    static func binding(for sample: HKSample) -> HealthKitFHIRBinding? {
        if let quantity = sample as? HKQuantitySample {
            return quantityBinding(for: quantity.quantityType.identifier)
        }
        if sample is HKCorrelation,
           sample.sampleType.identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
            return .bloodPressure
        }
        if sample is HKCategorySample,
           sample.sampleType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            return .sleepStage
        }
        return nil
    }

    // A closed source-type dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity
    private static func quantityBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKQuantityTypeIdentifier(rawValue: identifier) {
        case .activeEnergyBurned:
            return .quantity(.activeEnergy, unit: .kilocalorie(), display: "kcal")
        case .basalBodyTemperature:
            return .quantity(.basalBodyTemperature, unit: .degreeCelsius(), display: "Cel")
        case .bodyMass:
            return .quantity(.bodyWeight, unit: .gramUnit(with: .kilo), display: "kg")
        case .height:
            return .quantity(.bodyHeight, unit: .meterUnit(with: .centi), display: "cm")
        case .bodyMassIndex:
            return .quantity(.bodyMassIndex, unit: .count(), display: "kg/m2")
        case .bodyTemperature:
            return .quantity(.bodyTemperature, unit: .degreeCelsius(), display: "Cel")
        case .respiratoryRate:
            return .quantity(.respiratoryRate, unit: .count().unitDivided(by: .minute()), display: "breaths/minute")
        case .oxygenSaturation:
            return .percent(.oxygenSaturation)
        case .heartRate:
            return .quantity(.heartRate, unit: .count().unitDivided(by: .minute()), display: "beats/minute")
        case .stepCount:
            return .quantity(.stepCount, unit: .count(), display: "steps")
        case .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .distanceWheelchair,
             .distanceDownhillSnowSports,
             .distanceCrossCountrySkiing,
             .distancePaddleSports,
             .distanceRowing,
             .distanceSkatingSports:
            return .quantity(.distance, unit: .meter(), display: "m")
        default:
            return nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitFHIRBinding: Sendable {
    case quantity(HealthKitFHIRObservationContract, unit: HKUnit, display: String)
    case percent(HealthKitFHIRObservationContract)
    case bloodPressure
    case sleepStage

    var contract: HealthKitFHIRObservationContract {
        switch self {
        case .quantity(let contract, _, _), .percent(let contract):
            contract
        case .bloodPressure:
            HealthKitFHIRObservationContract(shared: GroveFHIRMeasurementCatalog.bloodPressure)
        case .sleepStage:
            HealthKitFHIRObservationContract(shared: GroveFHIRMeasurementCatalog.sleepStage)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRObservationContract {
    static let activeEnergy = Self(shared: GroveFHIRMeasurementCatalog.activeEnergy)
    static let basalBodyTemperature = Self(shared: GroveFHIRMeasurementCatalog.basalBodyTemperature)
    static let bodyWeight = Self(shared: GroveFHIRMeasurementCatalog.bodyWeight)
    static let bodyHeight = Self(shared: GroveFHIRMeasurementCatalog.bodyHeight)
    static let bodyTemperature = Self(shared: GroveFHIRMeasurementCatalog.bodyTemperature)
    static let respiratoryRate = Self(shared: GroveFHIRMeasurementCatalog.respiratoryRate)
    static let oxygenSaturation = Self(shared: GroveFHIRMeasurementCatalog.oxygenSaturation)
    static let heartRate = Self(shared: GroveFHIRMeasurementCatalog.heartRate)
    static let stepCount = Self(shared: GroveFHIRMeasurementCatalog.stepCount)
    static let distance = Self(shared: GroveFHIRMeasurementCatalog.distance)
}

// swiftlint:enable file_types_order

#endif
