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


/// The codings of a HealthKit metadata value in the adapter CodeSystem that names its cases.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MetadataVocabulary: Sendable {
    /// The coding of each admitted value, by raw value.
    let codings: [Int: Coding]

    /// The vocabulary of one HealthKit enumeration, each case's code and display in `system`.
    init<Value: RawRepresentable>(
        _ vocabulary: Value.Type,
        system: FHIRPrimitive<FHIRURI>,
        codes: KeyValuePairs<Value, (code: String, display: String)>
    ) where Value.RawValue == Int {
        let codings = codes.map { value, code in
            (value.rawValue, Coding(code: code.code.asFHIRStringPrimitive(), display: code.display.asFHIRStringPrimitive(), system: system))
        }
        self.codings = Dictionary(codings) { first, _ in first }
    }
}


/// A closed HealthKit category vocabulary and the codings each of its values becomes.
///
/// A value reports as one shared code in its contract's result CodeSystem, followed by the exact HealthKit case in the
/// adapter's own CodeSystem when the table keeps one; a notification's table keeps none, because the source-type
/// coding already carries the lineage. A value the table does not list is unsupported.
@available(iOS 18, macOS 15, watchOS 11, *)
struct CodedTable: Sendable {
    /// The codes one HealthKit value becomes.
    struct Row: Sendable {
        /// The shared code.
        let shared: String
        /// The shared code's display where the contract lists the code without one (severity, presence and sleep,
        /// whose contracts publish allowed values but no result codes); otherwise the contract's display is stated.
        let sharedDisplay: String?
        /// The HealthKit case's code in the table's source CodeSystem.
        let source: String?
        /// The HealthKit case's display.
        let sourceDisplay: String?

        /// The codes of one value.
        init(_ shared: String, _ sharedDisplay: String? = nil, source: String? = nil, _ sourceDisplay: String? = nil) {
            self.shared = shared
            self.sharedDisplay = sharedDisplay
            self.source = source
            self.sourceDisplay = sourceDisplay
        }
    }

    /// The adapter CodeSystem of the HealthKit cases, or `nil` when the shared code alone states the value.
    let sourceSystem: FHIRPrimitive<FHIRURI>?
    /// Every value the table maps, by HealthKit raw value, in the order written.
    let rows: [(raw: Int, row: Row)]

    /// The table of one HealthKit vocabulary.
    init<Value: RawRepresentable>(
        _ vocabulary: Value.Type,
        sourceSystem: FHIRPrimitive<FHIRURI>?,
        rows: KeyValuePairs<Value, Row>
    ) where Value.RawValue == Int {
        self.sourceSystem = sourceSystem
        self.rows = rows.map { (raw: $0.key.rawValue, row: $0.value) }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CodedTable {
    /// A symptom's severity.
    static let severity = CodedTable(
        HKCategoryValueSeverity.self,
        sourceSystem: Canonicals.healthKitSymptomSeverity,
        rows: [
            .unspecified: Row("present", "Present, severity unspecified", source: "unspecified", "Unspecified"),
            .notPresent: Row("not-present", "Not present", source: "notPresent", "Not present"),
            .mild: Row("mild", "Mild", source: "mild", "Mild"),
            .moderate: Row("moderate", "Moderate", source: "moderate", "Moderate"),
            .severe: Row("severe", "Severe", source: "severe", "Severe")
        ]
    )

    /// Whether a symptom without a severity grade was present.
    static let presence = CodedTable(
        HKCategoryValuePresence.self,
        sourceSystem: Canonicals.healthKitPresence,
        rows: [
            .present: Row("present", "Present, severity unspecified", source: "present", "Present"),
            .notPresent: Row("not-present", "Not present", source: "notPresent", "Not present")
        ]
    )

    /// A sleep stage; HealthKit's core sleep is the shared vocabulary's light sleep.
    static let sleep = CodedTable(
        HKCategoryValueSleepAnalysis.self,
        sourceSystem: Canonicals.healthKitSleepAnalysis,
        rows: [
            .inBed: Row("in-bed", "In bed", source: "inBed", "In bed"),
            .asleepUnspecified: Row("asleep-unspecified", "Asleep, unspecified stage", source: "asleepUnspecified", "Asleep, unspecified"),
            .awake: Row("awake", "Awake", source: "awake", "Awake"),
            .asleepCore: Row("light", "Light sleep", source: "asleepCore", "Asleep, core"),
            .asleepDeep: Row("deep", "Deep sleep", source: "asleepDeep", "Asleep, deep"),
            .asleepREM: Row("rem", "REM sleep", source: "asleepREM", "Asleep, REM")
        ]
    )

    /// A change in appetite.
    static let appetiteChanges = CodedTable(
        HKCategoryValueAppetiteChanges.self,
        sourceSystem: Canonicals.healthKitAppetiteChanges,
        rows: [
            .unspecified: Row("change-unspecified", source: "unspecified", "Unspecified"),
            .noChange: Row("no-change", source: "noChange", "No change"),
            .decreased: Row("decreased", source: "decreased", "Decreased"),
            .increased: Row("increased", source: "increased", "Increased")
        ]
    )

    /// Whether the person stood during an hour.
    static let appleStandHour = CodedTable(
        HKCategoryValueAppleStandHour.self,
        sourceSystem: Canonicals.healthKitAppleStandHourValue,
        rows: [
            .stood: Row("stood", source: "stood", "Stood"),
            .idle: Row("idle", source: "idle", "Idle")
        ]
    )

    /// The quality of cervical mucus.
    static let cervicalMucusQuality = CodedTable(
        HKCategoryValueCervicalMucusQuality.self,
        sourceSystem: Canonicals.healthKitCervicalMucusQuality,
        rows: [
            .dry: Row("dry", source: "dry", "Dry"),
            .sticky: Row("sticky", source: "sticky", "Sticky"),
            .creamy: Row("creamy", source: "creamy", "Creamy"),
            .watery: Row("watery", source: "watery", "Watery"),
            .eggWhite: Row("egg-white", source: "eggWhite", "Egg white")
        ]
    )

    /// The contraceptive in use.
    static let contraceptive = CodedTable(
        HKCategoryValueContraceptive.self,
        sourceSystem: Canonicals.healthKitContraceptive,
        rows: [
            .unspecified: Row("unspecified", source: "unspecified", "Unspecified"),
            .implant: Row("implant", source: "implant", "Implant"),
            .injection: Row("injection", source: "injection", "Injection"),
            .intrauterineDevice: Row("intrauterine-device", source: "intrauterineDevice", "Intrauterine device"),
            .intravaginalRing: Row("intravaginal-ring", source: "intravaginalRing", "Intravaginal ring"),
            .oral: Row("oral", source: "oral", "Oral"),
            .patch: Row("patch", source: "patch", "Patch")
        ]
    )

    /// An ovulation test's result; an estrogen surge reports as the shared high-fertility result.
    static let ovulationTestResult = CodedTable(
        HKCategoryValueOvulationTestResult.self,
        sourceSystem: Canonicals.healthKitOvulationTestResult,
        rows: [
            .negative: Row("negative", source: "negative", "Negative"),
            .luteinizingHormoneSurge: Row("luteinizing-hormone-surge", source: "luteinizingHormoneSurge", "Luteinizing hormone surge"),
            .indeterminate: Row("indeterminate", source: "indeterminate", "Indeterminate"),
            .estrogenSurge: Row("high-fertility", source: "estrogenSurge", "Estrogen surge")
        ]
    )

    /// A pregnancy or progesterone test's result, which HealthKit states in one shared vocabulary.
    static let testResult = CodedTable(
        HKCategoryValuePregnancyTestResult.self,
        sourceSystem: Canonicals.healthKitTestResult,
        rows: [
            .negative: Row("negative", source: "negative", "Negative"),
            .positive: Row("positive", source: "positive", "Positive"),
            .indeterminate: Row("indeterminate", source: "indeterminate", "Indeterminate")
        ]
    )

    /// The amount of vaginal bleeding, which menstrual flow states too.
    static let vaginalBleeding = CodedTable(
        HKCategoryValueVaginalBleeding.self,
        sourceSystem: Canonicals.healthKitVaginalBleeding,
        rows: [
            .unspecified: Row("unspecified", source: "unspecified", "Unspecified"),
            .light: Row("light", source: "light", "Light"),
            .medium: Row("medium", source: "medium", "Medium"),
            .heavy: Row("heavy", source: "heavy", "Heavy"),
            .none: Row("none", source: "none", "None")
        ]
    )
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CodedTable {
    /// A low-cardio-fitness notification.
    static let lowCardioFitness = CodedTable(
        HKCategoryValueLowCardioFitnessEvent.self,
        sourceSystem: nil,
        rows: [.lowFitness: Row("low-fitness")]
    )

    /// A walking-steadiness notification. The contract admits none of these codes, since the guide splits each into a
    /// value and an occurrence component, so every value has no normative code and is a compile defect.
    static let walkingSteadiness = CodedTable(
        HKCategoryValueAppleWalkingSteadinessEvent.self,
        sourceSystem: nil,
        rows: [
            .initialLow: Row("initial-low"),
            .initialVeryLow: Row("initial-very-low"),
            .repeatLow: Row("repeat-low"),
            .repeatVeryLow: Row("repeat-very-low")
        ]
    )

    /// An environmental-audio-exposure notification.
    static let environmentalAudioExposure = CodedTable(
        HKCategoryValueEnvironmentalAudioExposureEvent.self,
        sourceSystem: nil,
        rows: [.momentaryLimit: Row("momentary-limit")]
    )

    /// A headphone-audio-exposure notification.
    static let headphoneAudioExposure = CodedTable(
        HKCategoryValueHeadphoneAudioExposureEvent.self,
        sourceSystem: nil,
        rows: [.sevenDayLimit: Row("seven-day-limit")]
    )
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension MetadataVocabulary {
    /// The motion context HealthKit states for a heart-rate reading.
    static let heartRateMotionContext = MetadataVocabulary(
        HKHeartRateMotionContext.self,
        system: Canonicals.healthKitHeartRateMotionContext,
        codes: [
            .notSet: ("not-set", "Not Set"),
            .sedentary: ("sedentary", "Sedentary"),
            .active: ("active", "Active")
        ]
    )

    /// Why insulin was delivered.
    static let insulinDeliveryReason = MetadataVocabulary(
        HKInsulinDeliveryReason.self,
        system: Canonicals.healthKitInsulinDeliveryReason,
        codes: [
            .basal: ("basal", "Basal"),
            .bolus: ("bolus", "Bolus")
        ]
    )
}

#endif
