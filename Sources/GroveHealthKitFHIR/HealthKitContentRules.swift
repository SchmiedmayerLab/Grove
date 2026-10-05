//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


/// The facts of the HealthKit content mapping that the pinned guide does not carry, written by hand.
///
/// A source type's rule says only how its value is read; everything else comes from the generated contract of its
/// inventory row's first measurement, so no rule names a contract or a profile. A supported quantity or scored
/// assessment needs no listed rule: its row implies one. ``HealthKitContentPlan`` compiles the rules against the
/// contracts once per process.
@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitContentRules {
    /// How one source type converts.
    enum Rule: Sendable {
        /// One Observation of the row's first measurement, its value read as the observation rule says.
        case observation(ObservationRule)
        /// The ECG waveform and its derived average heart rate, built only from the caller's ECG record.
        case electrocardiogram
        /// A recording document of the registered format with a fixed title, built only from the caller's record.
        case recording(RegisteredRecordingFormat, title: String)
        /// A CDA document, carried byte for byte under the document's own title, else under this one.
        case clinicalDocument(title: String)
        /// A provider-issued FHIR resource, carried byte for byte and typed by its clinical record type code.
        case clinicalRecord(typeCode: String)
    }

    /// How an Observation's value is read from its sample.
    enum ObservationRule: Sendable {
        /// The sample's quantity.
        case quantity(QuantitySource)
        /// A category value, coded through the table.
        case coded(CodedTable)
        /// A category sample that states only that it occurred, reported as the contract's one result code.
        case occurrence
        /// A category sample's duration, in the contract's unit.
        case duration
        /// Whether protection was used, from `HKMetadataKeySexualActivityProtectionUsed`.
        case protection
        /// The blood-pressure correlation's members, one component each.
        case bloodPressure
        /// The workout's activity, totals and heart-rate statistics.
        case workout
        /// The reflection's valence and its coded axes.
        case stateOfMind
    }

    /// Where a quantity value comes from.
    enum QuantitySource: Sendable {
        /// The sample's quantity as its contract states it: in the HealthKit unit of the contract's UCUM code, or, for
        /// a contract in percent, the fraction HealthKit keeps, stated in percent.
        case contract
        /// A per-session rate HealthKit already computed, read as a plain count and never divided again.
        case platformRate
        /// A scored assessment's score.
        case score
    }

    /// One rule and every source type it applies to; a type listed under two rules is a compile defect.
    struct RuleGroup: Sendable {
        /// The rule.
        let rule: Rule
        /// The source types, in inventory order.
        let types: [HealthKitSourceType]

        /// The group of `types` under `rule`.
        init(_ rule: Rule, _ types: [HealthKitSourceType]) {
            self.rule = rule
            self.types = types
        }
    }

    /// The output role of a recording document. The guide names it only in prose: "Use the exact measurement id,
    /// native-recording, clinical-record, or other output role declared by the catalog row."
    static let nativeRecordingRole = "native-recording"
    /// The output role of a clinical record or CDA document.
    static let clinicalRecordRole = "clinical-record"
    /// The CodeSystem of the clinical record type a carried FHIR resource is typed by.
    static let clinicalRecordTypeSystem = FHIRPrimitive(
        FHIRURI(stringLiteral: "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-clinical-record-type")
    )

    /// Supported rows the adapter declares it does not convert yet; any other supported row without a rule is a defect.
    static let notYetConvertible: Set<HealthKitSourceType> = [
        .biologicalSex, .bloodType, .dateOfBirth, .fitzpatrickSkinType, .wheelchairUse, .food, .audiogram
    ]

    /// The correlation members, by contract component id; a member type alone converts only inside its correlation.
    static let bloodPressureMembers: KeyValuePairs<String, HealthKitSourceType> = [
        "systolic": .bloodPressureSystolic,
        "diastolic": .bloodPressureDiastolic
    ]

    /// The HealthKit unit each UCUM code the adapter reads is read in.
    ///
    /// HealthKit cannot parse UCUM (`HKUnit(from: "Cel")` raises), so the correspondence is stated, once per code: a
    /// quantity contract whose code is missing here does not compile. Body-mass index is a plain ratio in HealthKit;
    /// `mV` is the ECG claim's voltage unit.
    static let ucumUnits: [String: HKUnit] = [
        "/min": .count().unitDivided(by: .minute()),
        "Cel": .degreeCelsius(),
        "L": .liter(),
        "L/min": .liter().unitDivided(by: .minute()),
        "W": .watt(),
        "[iU]": .internationalUnit(),
        "cm": .meterUnit(with: .centi),
        "dB[SPL]": .decibelAWeightedSoundPressureLevel(),
        "g": .gram(),
        "kcal": .kilocalorie(),
        "kcal/kg/h": .kilocalorie().unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .hour()),
        "kg": .gramUnit(with: .kilo),
        "kg/m2": .count(),
        "m": .meter(),
        "m/s": .meter().unitDivided(by: .second()),
        "mL": .literUnit(with: .milli),
        "mL/kg/min": .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute()),
        "mV": .voltUnit(with: .milli),
        "mg": .gramUnit(with: .milli),
        "mg/dL": .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)),
        "min": .minute(),
        "mm[Hg]": .millimeterOfMercury(),
        "ms": .secondUnit(with: .milli),
        "uS": .siemenUnit(with: .micro),
        "ug": .gramUnit(with: .micro),
        "{drinks}": .count(),
        "{falls}": .count(),
        "{flights}": .count(),
        "{puff}": .count(),
        "{pushes}": .count(),
        "{score}": .appleEffortScore(),
        "{steps}": .count(),
        "{strokes}": .count(),
        "{uvindex}": .count()
    ]

    /// How many seconds one unit of a duration contract's UCUM code lasts.
    static let durationUnits: [String: Double] = ["s": 1, "min": 60]

    /// The categories Grove states for measurements the catalog fixes none for.
    static let categories: [String: CodingContract] = [
        "body-mass-index": category("vital-signs", "Vital Signs"),
        "step-count": category("activity", "Activity"),
        "distance": category("activity", "Activity"),
        "active-energy": category("activity", "Activity"),
        "sleep-stage": category("activity", "Activity")
    ]

    /// Period measurements that must span a non-zero interval: step and wheelchair-push counts obey the guide's
    /// invariant `grove-step-count-period-1` (`end > start`), and the shared mobile-semantics corpus states "The
    /// Period is non-zero" for basal energy and mindfulness sessions. Every other Period admits `start == end`.
    static let nonZeroPeriods: Set<String> = [
        MeasurementCatalog.stepCount.id,
        MeasurementCatalog.wheelchairPushCount.id,
        MeasurementCatalog.basalEnergy.id,
        MeasurementCatalog.mindfulnessSession.id
    ]

    /// The category a measurement's Observation states: the catalog's, else Grove's own.
    static func category(of contract: MeasurementContract) -> CodingContract? {
        contract.category ?? categories[contract.id]
    }

    /// The rule a supported row implies when no group lists its type, from the SDK type its identifier names: a
    /// quantity type reads its contract's quantity and a scored assessment its score. Any other row implies none.
    static func impliedRule(of type: HealthKitSourceType, status: HealthKitImplementationStatus) -> Rule? {
        guard status == .supported else {
            return nil
        }
        if type.rawValue.hasPrefix("HKQuantityTypeIdentifier") {
            return .observation(.quantity(.contract))
        }
        if type.rawValue.hasPrefix("HKScoredAssessmentTypeIdentifier") {
            return .observation(.quantity(.score))
        }
        return nil
    }

    /// The metadata a source type states as a component of its Observation, if any.
    static func metadataComponent(
        of type: HealthKitSourceType,
        contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> MetadataComponentRule? {
        switch type {
        case .heartRate: .heartRateMotionContext
        case .insulinDelivery: .insulinDeliveryReason
        case .menstrualFlow: try .menstrualCycleStart(contract)
        default: nil
        }
    }

    /// An HL7 Observation category.
    private static func category(_ code: String, _ display: String) -> CodingContract {
        CodingContract(system: "http://terminology.hl7.org/CodeSystem/observation-category", code: code, display: display)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitContentRules {
    /// Every listed source type's rule, grouped; a type the groups do not list converts under the rule its row implies,
    /// else is refused.
    static let groups: [RuleGroup] = categoryGroups + recordGroups

    /// The category rules.
    private static let categoryGroups = [
        RuleGroup(.observation(.coded(.severity)), [
            .abdominalCramps, .acne, .bladderIncontinence, .bloating, .breastPain, .chestTightnessOrPain, .chills,
            .constipation, .coughing, .diarrhea, .dizziness, .drySkin, .fainting, .fatigue, .fever, .generalizedBodyAche,
            .hairLoss, .headache, .heartburn, .hotFlashes, .lossOfSmell, .lossOfTaste, .lowerBackPain, .memoryLapse, .nausea,
            .nightSweats, .pelvicPain, .rapidPoundingOrFlutteringHeartbeat, .runnyNose, .shortnessOfBreath, .sinusCongestion,
            .skippedHeartbeat, .soreThroat, .vaginalDryness, .vomiting, .wheezing
        ]),
        RuleGroup(.observation(.coded(.presence)), [.moodChanges, .sleepChanges]),
        RuleGroup(.observation(.coded(.sleep)), [.sleepAnalysis]),
        RuleGroup(.observation(.coded(.appetiteChanges)), [.appetiteChanges]),
        RuleGroup(.observation(.coded(.appleStandHour)), [.appleStandHour]),
        RuleGroup(.observation(.coded(.cervicalMucusQuality)), [.cervicalMucusQuality]),
        RuleGroup(.observation(.coded(.contraceptive)), [.contraceptive]),
        RuleGroup(.observation(.coded(.ovulationTestResult)), [.ovulationTestResult]),
        RuleGroup(.observation(.coded(.testResult)), [.pregnancyTestResult, .progesteroneTestResult]),
        RuleGroup(.observation(.coded(.vaginalBleeding)), [.bleedingAfterPregnancy, .bleedingDuringPregnancy, .menstrualFlow]),
        RuleGroup(.observation(.coded(.lowCardioFitness)), [.lowCardioFitnessEvent]),
        RuleGroup(.observation(.coded(.walkingSteadiness)), [.appleWalkingSteadinessEvent]),
        RuleGroup(.observation(.coded(.environmentalAudioExposure)), [.audioExposureEvent]),
        RuleGroup(.observation(.coded(.headphoneAudioExposure)), [.headphoneAudioExposureEvent]),
        RuleGroup(.observation(.occurrence), [
            .highHeartRateEvent, .hypertensionEvent, .infrequentMenstrualCycles, .intermenstrualBleeding,
            .irregularHeartRhythmEvent, .irregularMenstrualCycles, .lactation, .lowHeartRateEvent,
            .persistentIntermenstrualBleeding, .pregnancy, .prolongedMenstrualPeriods, .sleepApneaEvent
        ]),
        RuleGroup(.observation(.duration), [.handwashingEvent, .mindfulSession, .toothbrushingEvent]),
        RuleGroup(.observation(.protection), [.sexualActivity])
    ]

    /// The rules of the remaining sample and record types. Sleeping breathing disturbances are the one quantity whose
    /// row does not imply its rule.
    private static let recordGroups = [
        RuleGroup(.observation(.quantity(.platformRate)), [.appleSleepingBreathingDisturbances]),
        RuleGroup(.observation(.bloodPressure), [.bloodPressure]),
        RuleGroup(.observation(.workout), [.workout]),
        RuleGroup(.observation(.stateOfMind), [.stateOfMind]),
        RuleGroup(.electrocardiogram, [.electrocardiogram]),
        RuleGroup(.recording(.beatIntervalSeries, title: "Heartbeat series beat intervals"), [.heartbeatSeries]),
        RuleGroup(.recording(.locationTrackSamples, title: "Workout route locations"), [.workoutRoute]),
        RuleGroup(.clinicalDocument(title: "Clinical document"), [.cda]),
        RuleGroup(.clinicalRecord(typeCode: "allergy-record"), [.allergyRecord]),
        RuleGroup(.clinicalRecord(typeCode: "clinical-note-record"), [.clinicalNoteRecord]),
        RuleGroup(.clinicalRecord(typeCode: "condition-record"), [.conditionRecord]),
        RuleGroup(.clinicalRecord(typeCode: "coverage-record"), [.coverageRecord]),
        RuleGroup(.clinicalRecord(typeCode: "immunization-record"), [.immunizationRecord]),
        RuleGroup(.clinicalRecord(typeCode: "lab-result-record"), [.labResultRecord]),
        RuleGroup(.clinicalRecord(typeCode: "medication-record"), [.medicationRecord]),
        RuleGroup(.clinicalRecord(typeCode: "procedure-record"), [.procedureRecord]),
        RuleGroup(.clinicalRecord(typeCode: "vital-sign-record"), [.vitalSignRecord])
    ]
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuantityContract {
    /// The quantity's unit binding: its UCUM code and display unit, and the HealthKit unit the rules state for the
    /// code. A code the rules state no unit for is a defect.
    func binding() throws(HealthKitContentDefect) -> HealthKitCatalog.UnitBinding {
        guard let healthKitUnit = HealthKitContentRules.ucumUnits[code] else {
            throw HealthKitContentDefect("reads \(code), which has no HealthKit unit")
        }
        return HealthKitCatalog.UnitBinding(ucumCode: code, displayUnit: unit, unit: healthKitUnit)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension MeasurementContract {
    /// The quantity component `id`: the component it becomes and its quantity.
    func quantityComponent(_ id: String) throws(HealthKitContentDefect) -> (template: ComponentTemplate, quantity: QuantityContract) {
        guard let component = components.first(where: { $0.id == id }),
              let quantity = component.quantity,
              let template = ComponentTemplate(component) else {
            throw HealthKitContentDefect("states no quantity component \(id)")
        }
        return (template, quantity)
    }
}


extension [ResultCodeContract] {
    /// The concept of the published result `code`, with its display, in `system`; a code the list does not publish
    /// is a defect.
    func concept(_ code: String, system: String) throws(HealthKitContentDefect) -> CodeableConcept {
        guard let result = first(where: { $0.code == code }) else {
            throw HealthKitContentDefect("admits no result code \(code)")
        }
        return CodeableConcept(coding: [Coding(result.code, display: result.display, system: system)])
    }
}


extension Coding {
    /// A coding of `code` in `system`, which the contract must admit: a code `admitted` does not list is a defect.
    init(_ code: String, system: String, admittedBy admitted: [String]) throws(HealthKitContentDefect) {
        guard admitted.contains(code) else {
            throw HealthKitContentDefect("admits no code \(code) in \(system)")
        }
        self.init(code, system: system)
    }
}

#endif
