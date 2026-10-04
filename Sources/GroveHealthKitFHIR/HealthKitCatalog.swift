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


/// One measurement and its exact direct profile claims in the HealthKit adapter matrix.
public struct HealthKitMeasurementContract: Sendable {
    public let id: String
    public let profiles: [FHIRPrimitive<Canonical>]
}


struct HealthKitFHIRObservationContract: Sendable {
    static let bodyMassIndex = HealthKitFHIRObservationContract(
        measurement: HealthKitMeasurementContract(
            id: "body-mass-index",
            profiles: HealthKitContract.bodyMassIndexProfiles
        ),
        code: CodingContract(system: "http://loinc.org", code: "39156-5"),
        requiredCodings: [],
        quantity: QuantityContract(
            system: "http://unitsofmeasure.org",
            code: "kg/m2",
            unit: "kg/m2"
        ),
        effective: .dateTime
    )

    let measurement: HealthKitMeasurementContract
    let code: CodingContract
    let requiredCodings: [CodingContract]
    let quantity: QuantityContract?
    let components: [ComponentContract]
    let resultCodeSystem: String?
    let measurementResultCodes: [ResultCodeContract]
    let method: MethodContract?
    let effective: MeasurementEffective

    var id: String { measurement.id }
    var profiles: [FHIRPrimitive<Canonical>] { measurement.profiles }

    init(shared: MeasurementContract) {
        let profiles: [FHIRPrimitive<Canonical>]
        if ProfileClaims.singleObservationProfiles.contains(shared.profile) {
            profiles = [shared.profile]
        } else {
            profiles = ProfileClaims.observation(
                sharedMeasurement: shared.profile,
                adapter: Profile.healthkitObservation
            )
        }
        self.measurement = HealthKitMeasurementContract(
            id: shared.id,
            profiles: profiles
        )
        self.code = shared.code
        self.requiredCodings = shared.requiredCodings
        self.quantity = shared.quantity
        self.components = shared.components
        self.resultCodeSystem = shared.resultCodeSystem
        self.measurementResultCodes = shared.resultCodes
        self.method = shared.method
        self.effective = shared.effective
    }

    private init(
        measurement: HealthKitMeasurementContract,
        code: CodingContract,
        requiredCodings: [CodingContract] = [],
        quantity: QuantityContract?,
        components: [ComponentContract] = [],
        resultCodeSystem: String? = nil,
        effective: MeasurementEffective
    ) {
        self.measurement = measurement
        self.code = code
        self.requiredCodings = requiredCodings
        self.quantity = quantity
        self.components = components
        self.resultCodeSystem = resultCodeSystem
        self.measurementResultCodes = []
        self.method = nil
        self.effective = effective
    }
}


/// One output a source type's conversion mints, and how a retraction names it.
public struct HealthKitOutput: Hashable, Sendable {
    public let role: String
    public let discriminator: String
    public let resourceType: ResourceType
    public let retractionRole: RetractionTargetRole
}


/// One authoritative row in the HealthKit implementation matrix.
public struct HealthKitCatalogEntry: Sendable {
    public let sourceTypeIdentifier: String
    public let title: String
    /// The one selected contract, or all candidate contracts when source facts cannot select one.
    public let measurements: [HealthKitMeasurementContract]
    public let implementationStatus: HealthKitImplementationStatus
    public let requirement: String?
}


/// Closed, fail-closed catalog used by ``HealthKitConverter``.
///
/// This catalog alone determines whether the public API may claim a Grove profile.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum HealthKitCatalog {
    /// Every platform identifier in the frozen HealthKit inventory, including characteristics
    /// and other non-sample identifiers that are outside this converter's input type. The
    /// sleep-duration aggregate lives in the catalog's derivedAggregates, not in these rows.
    /// A consumer can render this directly as the implementation coverage matrix.
    public static let entries: [HealthKitCatalogEntry] = HealthKitContentPlan.all.map(\.entry)

    /// Every output the converter mints for one source type, in the order the graph emits them.
    ///
    /// A caller holding only a source type — a deletion, whose sample is already gone — names the outputs an
    /// addition minted. One exception: an ECG's average-heart-rate child is listed whether or not the ECG stated an
    /// average, so the retraction of an ECG without one also names a child that was never emitted. A deletion cannot
    /// tell the two apart, and the pinned guide has no source-record retraction scope yet (an IG gap; a draft
    /// exists); a receiver resolves the extra target to nothing.
    public static func outputs(for type: HealthKitSourceType) -> [HealthKitOutput] {
        HealthKitContentPlan[type].outputs.map(\.output)
    }

    static func binding(for sample: HKSample) -> HealthKitFHIRBinding? {
        if sample is HKWorkout {
            return .workout
        }
        if sample is HKStateOfMind {
            return .stateOfMind
        }
        return binding(forSourceTypeIdentifier: sample.sampleType.identifier)
    }

    static func binding(forSourceTypeIdentifier identifier: String) -> HealthKitFHIRBinding? {
        if identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
            return .bloodPressure
        }
        if identifier == HKWorkoutType.workoutType().identifier {
            return .workout
        }
        if identifier == HKSampleType.stateOfMindType().identifier {
            return .stateOfMind
        }
        return quantityBinding(for: identifier)
            ?? categoryBinding(for: identifier)
            ?? assessmentBinding(for: identifier)
    }

    private static func assessmentBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKScoredAssessmentTypeIdentifier(rawValue: identifier) {
        case .GAD7:
            .assessmentScore(HealthKitMeasurementCatalog.gad7Assessment)
        case .PHQ9:
            .assessmentScore(HealthKitMeasurementCatalog.phq9Assessment)
        default:
            nil
        }
    }

    /// The inventory row of a source type; every generated type has one.
    public static subscript(type: HealthKitSourceType) -> HealthKitCatalogEntry {
        HealthKitContentPlan[type].entry
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
    /// A device notification whose HealthKit value selects one published result code.
    ///
    /// The notification's own value set is the shared result code list; there is no separate adapter
    /// source vocabulary to absorb, because the source type coding already carries the lineage.
    case notification(HealthKitFHIRObservationContract, values: [Int: String])
    case sexualActivity
    case bloodPressure
    case sleepStage
    case workout
    case stateOfMind

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
             .fixedCode(let contract),
             .notification(let contract, _):
            contract
        case .sexualActivity:
            HealthKitFHIRObservationContract(shared: MeasurementCatalog.sexualActivity)
        case .bloodPressure:
            HealthKitFHIRObservationContract(shared: MeasurementCatalog.bloodPressure)
        case .sleepStage:
            HealthKitFHIRObservationContract(shared: MeasurementCatalog.sleepStage)
        case .workout:
            HealthKitFHIRObservationContract(shared: MeasurementCatalog.workout)
        case .stateOfMind:
            HealthKitFHIRObservationContract(shared: HealthKitMeasurementCatalog.stateOfMind)
        }
    }

    static func quantity(_ shared: MeasurementContract, unit: HKUnit) -> Self {
        .quantity(HealthKitFHIRObservationContract(shared: shared), unit: unit)
    }

    static func percent(_ shared: MeasurementContract) -> Self {
        .percent(HealthKitFHIRObservationContract(shared: shared))
    }

    static func sessionRate(_ shared: MeasurementContract) -> Self {
        .sessionRate(HealthKitFHIRObservationContract(shared: shared))
    }

    static func sessionDuration(_ shared: MeasurementContract) -> Self {
        .sessionDuration(HealthKitFHIRObservationContract(shared: shared))
    }

    static func assessmentScore(_ shared: MeasurementContract) -> Self {
        .assessmentScore(HealthKitFHIRObservationContract(shared: shared))
    }

    static func severity(_ shared: MeasurementContract) -> Self {
        .severity(HealthKitFHIRObservationContract(shared: shared))
    }

    static func presence(_ shared: MeasurementContract) -> Self {
        .presence(HealthKitFHIRObservationContract(shared: shared))
    }

    static func categoryValue(
        _ shared: MeasurementContract,
        absorption: HealthKitFHIRCategoryValueAbsorption
    ) -> Self {
        .categoryValue(HealthKitFHIRObservationContract(shared: shared), absorption: absorption)
    }

    static func fixedCode(_ shared: MeasurementContract) -> Self {
        .fixedCode(HealthKitFHIRObservationContract(shared: shared))
    }

    static func notification(_ shared: MeasurementContract, values: [Int: String] = [:]) -> Self {
        .notification(HealthKitFHIRObservationContract(shared: shared), values: values)
    }
}

// swiftlint:enable file_types_order

#endif
