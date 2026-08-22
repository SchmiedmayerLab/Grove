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


/// Implementation state of one HealthKit input in the Swift producer.
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
    let measurementResultCodes: [GroveFHIRResultCodeContract]
    let method: GroveFHIRMethodContract?
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
        self.measurementResultCodes = shared.resultCodes
        self.method = shared.method
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
        self.measurementResultCodes = []
        self.method = nil
        self.effective = effective
    }
}


/// One authoritative row in the HealthKit implementation matrix.
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
/// This catalog alone determines whether the public API may claim a Grove profile.
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
            measurements: measurements(for: row),
            implementationStatus: row.implementationStatus,
            requirement: row.requirement
        )
    }

    /// Bulk export converts tens of thousands of samples, so the row lookup is a hashed
    /// index rather than a scan over every platform identifier.
    private static let entriesBySourceTypeIdentifier = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.sourceTypeIdentifier, $0) }
    )

    static func entry(for sample: HKSample) -> HealthKitFHIRCatalogEntry? {
        entry(forSourceTypeIdentifier: sample.sampleType.identifier)
    }

    static func entry(forSourceTypeIdentifier identifier: String) -> HealthKitFHIRCatalogEntry? {
        entriesBySourceTypeIdentifier[identifier]
    }

    static func binding(for sample: HKSample) -> HealthKitFHIRBinding? {
        binding(forSourceTypeIdentifier: sample.sampleType.identifier)
    }

    static func binding(forSourceTypeIdentifier identifier: String) -> HealthKitFHIRBinding? {
        if identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
            return .bloodPressure
        }
        return quantityBinding(for: identifier)
            ?? categoryBinding(for: identifier)
            ?? assessmentBinding(for: identifier)
    }

    /// A multi-measurement row pairs each measurement with its own semantic profile; the
    /// remaining rows carry exactly the complete profile list of their one measurement.
    private static func measurements(for row: GroveFHIRHealthKitCatalogRow) -> [HealthKitFHIRMeasurementContract] {
        if row.measurementIDs.count > 1, row.measurementIDs.count == row.profiles.count {
            return zip(row.measurementIDs, row.profiles).map { id, profile in
                HealthKitFHIRMeasurementContract(id: id, profiles: [profile])
            }
        }
        return row.measurementIDs.map { id in
            HealthKitFHIRMeasurementContract(id: id, profiles: row.profiles)
        }
    }

    private static func assessmentBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKScoredAssessmentTypeIdentifier(rawValue: identifier) {
        case .GAD7:
            .assessmentScore(GroveFHIRHealthKitMeasurementCatalog.gad7Assessment)
        case .PHQ9:
            .assessmentScore(GroveFHIRHealthKitMeasurementCatalog.phq9Assessment)
        default:
            nil
        }
    }
}


/// The closed HealthKit category-value enumeration one coded binding absorbs.
enum HealthKitFHIRCategoryValueAbsorption: Sendable {
    case appetiteChanges
    case appleStandHour
    case cervicalMucusQuality
    case contraceptive
    case ovulationTestResult
    case pregnancyTestResult
    case progesteroneTestResult
    case vaginalBleeding
}


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitFHIRBinding: Sendable {
    case quantity(HealthKitFHIRObservationContract, unit: HKUnit)
    case percent(HealthKitFHIRObservationContract)
    case sessionRate(HealthKitFHIRObservationContract)
    case sessionDuration(HealthKitFHIRObservationContract)
    case assessmentScore(HealthKitFHIRObservationContract)
    case severity(HealthKitFHIRObservationContract)
    case presence(HealthKitFHIRObservationContract)
    case categoryValue(HealthKitFHIRObservationContract, absorption: HealthKitFHIRCategoryValueAbsorption)
    case fixedCode(HealthKitFHIRObservationContract)
    case sexualActivity
    case bloodPressure
    case sleepStage

    var contract: HealthKitFHIRObservationContract {
        switch self {
        case .quantity(let contract, _),
             .percent(let contract),
             .sessionRate(let contract),
             .sessionDuration(let contract),
             .assessmentScore(let contract),
             .severity(let contract),
             .presence(let contract),
             .categoryValue(let contract, _),
             .fixedCode(let contract):
            contract
        case .sexualActivity:
            HealthKitFHIRObservationContract(shared: GroveFHIRMeasurementCatalog.sexualActivity)
        case .bloodPressure:
            HealthKitFHIRObservationContract(shared: GroveFHIRMeasurementCatalog.bloodPressure)
        case .sleepStage:
            HealthKitFHIRObservationContract(shared: GroveFHIRMeasurementCatalog.sleepStage)
        }
    }

    static func quantity(_ shared: GroveFHIRMeasurementContract, unit: HKUnit) -> Self {
        .quantity(HealthKitFHIRObservationContract(shared: shared), unit: unit)
    }

    static func percent(_ shared: GroveFHIRMeasurementContract) -> Self {
        .percent(HealthKitFHIRObservationContract(shared: shared))
    }

    static func sessionRate(_ shared: GroveFHIRMeasurementContract) -> Self {
        .sessionRate(HealthKitFHIRObservationContract(shared: shared))
    }

    static func sessionDuration(_ shared: GroveFHIRMeasurementContract) -> Self {
        .sessionDuration(HealthKitFHIRObservationContract(shared: shared))
    }

    static func assessmentScore(_ shared: GroveFHIRMeasurementContract) -> Self {
        .assessmentScore(HealthKitFHIRObservationContract(shared: shared))
    }

    static func severity(_ shared: GroveFHIRMeasurementContract) -> Self {
        .severity(HealthKitFHIRObservationContract(shared: shared))
    }

    static func presence(_ shared: GroveFHIRMeasurementContract) -> Self {
        .presence(HealthKitFHIRObservationContract(shared: shared))
    }

    static func categoryValue(
        _ shared: GroveFHIRMeasurementContract,
        absorption: HealthKitFHIRCategoryValueAbsorption
    ) -> Self {
        .categoryValue(HealthKitFHIRObservationContract(shared: shared), absorption: absorption)
    }

    static func fixedCode(_ shared: GroveFHIRMeasurementContract) -> Self {
        .fixedCode(HealthKitFHIRObservationContract(shared: shared))
    }
}

// swiftlint:enable file_types_order

#endif
