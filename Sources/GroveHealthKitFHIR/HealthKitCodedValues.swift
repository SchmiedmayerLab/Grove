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
            (value.rawValue, Coding(code.code, display: code.display, system: system))
        }
        self.codings = Dictionary(codings) { first, _ in first }
    }
}


/// A closed HealthKit category vocabulary and the codings each of its values becomes.
///
/// A value reports as one shared code in its contract's result CodeSystem, followed by the exact HealthKit case in the
/// adapter's own CodeSystem when the table keeps one; a notification's table keeps none, because the source-type
/// coding already carries the lineage. A notification that HealthKit raises once and then repeats also states its
/// occurrence, in the contract's notification-occurrence component. A value the table does not list is unsupported.
@available(iOS 18, macOS 15, watchOS 11, *)
struct CodedTable: Sendable {
    /// The codes one HealthKit value becomes.
    struct Row: Sendable {
        /// The shared code.
        let shared: String
        /// The shared code's display where the contract lists the code without one (severity, presence and sleep,
        /// whose contracts publish allowed values but no result codes); otherwise the contract's display is stated.
        let display: String?
        /// The HealthKit case's code in the table's source CodeSystem.
        let source: String?
        /// The HealthKit case's display.
        let sourceDisplay: String?
        /// The notification-occurrence component's result code: whether the notification is the first at its
        /// classification or a repeat; `nil` when the value states no occurrence.
        let occurrence: String?

        /// The codes of one value.
        init(_ shared: String, display: String? = nil, source: String? = nil, sourceDisplay: String? = nil, occurrence: String? = nil) {
            self.shared = shared
            self.display = display
            self.source = source
            self.sourceDisplay = sourceDisplay
            self.occurrence = occurrence
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
            .unspecified: Row("present", display: "Present, severity unspecified", source: "unspecified", sourceDisplay: "Unspecified"),
            .notPresent: Row("not-present", display: "Not present", source: "notPresent", sourceDisplay: "Not present"),
            .mild: Row("mild", display: "Mild", source: "mild", sourceDisplay: "Mild"),
            .moderate: Row("moderate", display: "Moderate", source: "moderate", sourceDisplay: "Moderate"),
            .severe: Row("severe", display: "Severe", source: "severe", sourceDisplay: "Severe")
        ]
    )

    /// Whether a symptom without a severity grade was present.
    static let presence = CodedTable(
        HKCategoryValuePresence.self,
        sourceSystem: Canonicals.healthKitPresence,
        rows: [
            .present: Row("present", display: "Present, severity unspecified", source: "present", sourceDisplay: "Present"),
            .notPresent: Row("not-present", display: "Not present", source: "notPresent", sourceDisplay: "Not present")
        ]
    )

    /// A sleep stage; HealthKit's core sleep is the shared vocabulary's light sleep.
    static let sleep = CodedTable(
        HKCategoryValueSleepAnalysis.self,
        sourceSystem: Canonicals.healthKitSleepAnalysis,
        rows: [
            .inBed: Row("in-bed", display: "In bed", source: "inBed", sourceDisplay: "In bed"),
            .asleepUnspecified: Row(
                "asleep-unspecified", display: "Asleep, unspecified stage", source: "asleepUnspecified", sourceDisplay: "Asleep, unspecified"
            ),
            .awake: Row("awake", display: "Awake", source: "awake", sourceDisplay: "Awake"),
            .asleepCore: Row("light", display: "Light sleep", source: "asleepCore", sourceDisplay: "Asleep, core"),
            .asleepDeep: Row("deep", display: "Deep sleep", source: "asleepDeep", sourceDisplay: "Asleep, deep"),
            .asleepREM: Row("rem", display: "REM sleep", source: "asleepREM", sourceDisplay: "Asleep, REM")
        ]
    )

    /// A change in appetite.
    static let appetiteChanges = CodedTable(
        HKCategoryValueAppetiteChanges.self,
        sourceSystem: Canonicals.healthKitAppetiteChanges,
        rows: [
            .unspecified: Row("change-unspecified", source: "unspecified", sourceDisplay: "Unspecified"),
            .noChange: Row("no-change", source: "noChange", sourceDisplay: "No change"),
            .decreased: Row("decreased", source: "decreased", sourceDisplay: "Decreased"),
            .increased: Row("increased", source: "increased", sourceDisplay: "Increased")
        ]
    )

    /// Whether the person stood during an hour.
    static let appleStandHour = CodedTable(
        HKCategoryValueAppleStandHour.self,
        sourceSystem: Canonicals.healthKitAppleStandHourValue,
        rows: [
            .stood: Row("stood", source: "stood", sourceDisplay: "Stood"),
            .idle: Row("idle", source: "idle", sourceDisplay: "Idle")
        ]
    )

    /// The quality of cervical mucus.
    static let cervicalMucusQuality = CodedTable(
        HKCategoryValueCervicalMucusQuality.self,
        sourceSystem: Canonicals.healthKitCervicalMucusQuality,
        rows: [
            .dry: Row("dry", source: "dry", sourceDisplay: "Dry"),
            .sticky: Row("sticky", source: "sticky", sourceDisplay: "Sticky"),
            .creamy: Row("creamy", source: "creamy", sourceDisplay: "Creamy"),
            .watery: Row("watery", source: "watery", sourceDisplay: "Watery"),
            .eggWhite: Row("egg-white", source: "eggWhite", sourceDisplay: "Egg white")
        ]
    )

    /// The contraceptive in use.
    static let contraceptive = CodedTable(
        HKCategoryValueContraceptive.self,
        sourceSystem: Canonicals.healthKitContraceptive,
        rows: [
            .unspecified: Row("unspecified", source: "unspecified", sourceDisplay: "Unspecified"),
            .implant: Row("implant", source: "implant", sourceDisplay: "Implant"),
            .injection: Row("injection", source: "injection", sourceDisplay: "Injection"),
            .intrauterineDevice: Row("intrauterine-device", source: "intrauterineDevice", sourceDisplay: "Intrauterine device"),
            .intravaginalRing: Row("intravaginal-ring", source: "intravaginalRing", sourceDisplay: "Intravaginal ring"),
            .oral: Row("oral", source: "oral", sourceDisplay: "Oral"),
            .patch: Row("patch", source: "patch", sourceDisplay: "Patch")
        ]
    )

    /// An ovulation test's result; an estrogen surge reports as the shared high-fertility result.
    static let ovulationTestResult = CodedTable(
        HKCategoryValueOvulationTestResult.self,
        sourceSystem: Canonicals.healthKitOvulationTestResult,
        rows: [
            .negative: Row("negative", source: "negative", sourceDisplay: "Negative"),
            .luteinizingHormoneSurge: Row("luteinizing-hormone-surge", source: "luteinizingHormoneSurge", sourceDisplay: "Luteinizing hormone surge"),
            .indeterminate: Row("indeterminate", source: "indeterminate", sourceDisplay: "Indeterminate"),
            .estrogenSurge: Row("high-fertility", source: "estrogenSurge", sourceDisplay: "Estrogen surge")
        ]
    )

    /// A pregnancy or progesterone test's result, which HealthKit states in one shared vocabulary.
    static let testResult = CodedTable(
        HKCategoryValuePregnancyTestResult.self,
        sourceSystem: Canonicals.healthKitTestResult,
        rows: [
            .negative: Row("negative", source: "negative", sourceDisplay: "Negative"),
            .positive: Row("positive", source: "positive", sourceDisplay: "Positive"),
            .indeterminate: Row("indeterminate", source: "indeterminate", sourceDisplay: "Indeterminate")
        ]
    )

    /// The amount of vaginal bleeding, which menstrual flow states too.
    static let vaginalBleeding = CodedTable(
        HKCategoryValueVaginalBleeding.self,
        sourceSystem: Canonicals.healthKitVaginalBleeding,
        rows: [
            .unspecified: Row("unspecified", source: "unspecified", sourceDisplay: "Unspecified"),
            .light: Row("light", source: "light", sourceDisplay: "Light"),
            .medium: Row("medium", source: "medium", sourceDisplay: "Medium"),
            .heavy: Row("heavy", source: "heavy", sourceDisplay: "Heavy"),
            .none: Row("none", source: "none", sourceDisplay: "None")
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

    /// A walking-steadiness notification. The guide splits each HealthKit case in two: "Value is the severity
    /// classification and the notification-occurrence component is whether it is a first or repeat notification."
    static let walkingSteadiness = CodedTable(
        HKCategoryValueAppleWalkingSteadinessEvent.self,
        sourceSystem: nil,
        rows: [
            .initialLow: Row("low", occurrence: "initial"),
            .initialVeryLow: Row("very-low", occurrence: "initial"),
            .repeatLow: Row("low", occurrence: "repeat"),
            .repeatVeryLow: Row("very-low", occurrence: "repeat")
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
