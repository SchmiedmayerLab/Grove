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


struct HealthKitFHIRObservationContract: Sendable {
    static let bodyMassIndex = HealthKitFHIRObservationContract(
        measurement: HealthKitFHIRMeasurementContract(
            id: "body-mass-index",
            profiles: GroveFHIRHealthKitCatalog.bodyMassIndexProfiles
        ),
        code: GroveFHIRCodingContract(system: "http://loinc.org", code: "39156-5"),
        quantity: GroveFHIRQuantityContract(
            system: "http://unitsofmeasure.org",
            code: "kg/m2",
            unit: "kg/m2"
        ),
        effective: .dateTime
    )

    let measurement: HealthKitFHIRMeasurementContract
    let code: GroveFHIRCodingContract
    let quantity: GroveFHIRQuantityContract?
    let components: [GroveFHIRComponentContract]
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
        self.code = shared.code
        self.quantity = shared.quantity
        self.components = shared.components
        self.resultCodeSystem = shared.resultCodeSystem
        self.effective = shared.effective
    }

    private init(
        measurement: HealthKitFHIRMeasurementContract,
        code: GroveFHIRCodingContract,
        quantity: GroveFHIRQuantityContract?,
        components: [GroveFHIRComponentContract] = [],
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
    /// Every platform identifier in the frozen HealthKit inventory, including characteristics
    /// and other non-sample identifiers that are outside this converter's input type. The
    /// sleep-duration aggregate lives in the catalog's derivedAggregates, not in these rows.
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
            return .quantity(.activeEnergy, unit: .kilocalorie())
        case .basalBodyTemperature:
            return .quantity(.basalBodyTemperature, unit: .degreeCelsius())
        case .bodyMass:
            return .quantity(.bodyWeight, unit: .gramUnit(with: .kilo))
        case .height:
            return .quantity(.bodyHeight, unit: .meterUnit(with: .centi))
        case .bodyMassIndex:
            return .quantity(.bodyMassIndex, unit: .count())
        case .bodyTemperature:
            return .quantity(.bodyTemperature, unit: .degreeCelsius())
        case .respiratoryRate:
            return .quantity(.respiratoryRate, unit: .count().unitDivided(by: .minute()))
        case .oxygenSaturation:
            return .percent(.oxygenSaturation)
        case .heartRate:
            return .quantity(.heartRate, unit: .count().unitDivided(by: .minute()))
        case .stepCount:
            return .quantity(.stepCount, unit: .count())
        case .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .distanceWheelchair,
             .distanceDownhillSnowSports,
             .distanceCrossCountrySkiing,
             .distancePaddleSports,
             .distanceRowing,
             .distanceSkatingSports:
            return .quantity(.distance, unit: .meter())
        default:
            return nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitFHIRBinding: Sendable {
    case quantity(HealthKitFHIRObservationContract, unit: HKUnit)
    case percent(HealthKitFHIRObservationContract)
    case bloodPressure
    case sleepStage

    var contract: HealthKitFHIRObservationContract {
        switch self {
        case .quantity(let contract, _), .percent(let contract):
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
