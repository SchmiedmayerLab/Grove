//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import GroveHealthKit
public import ModelsR4


/// Controls how `HKCategorySample`s are mapped into FHIR Observations.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias CategoryTypesFHIRMapping = [SampleType<HKCategorySample>: CategoryTypeFHIRMapping]


/// Controls how an `HKCategorySample` is mapped into a FHIR Observation.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(codings:categories:)``
///
/// ### Instance Properties
/// - ``codings``
/// - ``categories``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct CategoryTypeFHIRMapping: Sendable {
    /// The FHIR `Coding`s to include in the resulting FHIR `Observation`.
    ///
    /// These codings will be appended to `code.coding` within the `Observation`.
    public var codings: [Coding]
    /// The FHIR `Coding`s to set as the resulting FHIR `Observation`'s `category`.
    ///
    /// Each coding is wrapped in its own `CodeableConcept` and appended to the `Observation`'s `category`.
    public var categories: [Coding]

    public init(codings: [Coding], categories: [Coding]) {
        self.codings = codings
        self.categories = categories
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Coding {
    init(_ sampleType: SampleType<HKCategorySample>) {
        self.init(
            code: sampleType.identifier.rawValue.asFHIRStringPrimitive(),
            display: sampleType.canonicalTitle.asFHIRStringPrimitive(),
            system: .healthKitSystem
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CategoryTypesFHIRMapping {
    /// The default FHIR mapping for HealthKit Category types
    public static let `default`: Self = { // swiftlint:disable:this closure_body_length
        // `categories` follows the observed concept: `survey` for what the user reports about themselves,
        // `activity` for what the body did (FHIR names sleep data in that definition), `social-history` for
        // lifestyle and environmental exposure, `laboratory` for a specimen test, `exam` for what a sensor
        // read off the body.
        // A standard coding is present only where LOINC or SNOMED CT covers the concept the type actually
        // records; where it does not, the HealthKit identifier stands alone and cross-source comparison of
        // that concept does not work. Apple's detection events have no standard equivalent by construction:
        // they assert that an algorithm fired, not that a finding is present.
        var mapping: Self = [:]
        /// Adds an entry to the mapping being built up
        ///
        /// - parameter sampleType: The `SampleType<HKCategorySample>` to which the entry belongs
        /// - parameter category: The FHIR observation category the concept belongs to
        /// - parameter extraCodings: Standard `Coding`s, ordered before the HealthKit identifier
        func addMapping(
            for sampleType: SampleType<HKCategorySample>,
            category: Coding,
            extraCodings: [Coding] = []
        ) {
            assert(mapping[sampleType] == nil, "Sample Type '\(sampleType)' already has an entry!")
            mapping[sampleType] = CategoryTypeFHIRMapping(
                codings: extraCodings + [Coding(sampleType)],
                categories: [category]
            )
        }
        /// Adds an entry whose concept SNOMED CT covers with a single code.
        func addMapping(
            for sampleType: SampleType<HKCategorySample>,
            category: Coding,
            snomed code: FHIRPrimitive<FHIRString>,
            _ display: FHIRPrimitive<FHIRString>
        ) {
            addMapping(
                for: sampleType,
                category: category,
                extraCodings: [Coding(code: code, display: display, system: .snomedCT)]
            )
        }

        // MARK: Activity and wellness

        addMapping(for: .appleStandHour, category: .activityCategory)
        addMapping(for: .appleWalkingSteadinessEvent, category: .activityCategory)
        addMapping(for: .handwashingEvent, category: .activityCategory)
        addMapping(for: .lowCardioFitnessEvent, category: .activityCategory)
        addMapping(for: .mindfulSession, category: .activityCategory)
        addMapping(for: .toothbrushingEvent, category: .activityCategory)
        // The stage codings LOINC does publish sit on the sample's value, where the stage actually is;
        // the type itself is "whatever HealthKit's sleep analysis reported", which no standard names.
        addMapping(for: .sleepAnalysis, category: .activityCategory)

        // MARK: Sensor-detected findings

        addMapping(for: .highHeartRateEvent, category: .examCategory)
        addMapping(for: .irregularHeartRhythmEvent, category: .examCategory)
        addMapping(for: .lowHeartRateEvent, category: .examCategory)

        // MARK: Lifestyle and exposure

        addMapping(for: .contraceptive, category: .socialHistoryCategory)
        addMapping(for: .environmentalAudioExposureEvent, category: .socialHistoryCategory)
        addMapping(for: .headphoneAudioExposureEvent, category: .socialHistoryCategory)
        addMapping(for: .sexualActivity, category: .socialHistoryCategory)
        addMapping(for: .lactation, category: .socialHistoryCategory, snomed: "63158009", "Lactation")
        addMapping(for: .pregnancy, category: .socialHistoryCategory, snomed: "77386006", "Pregnancy")

        // MARK: Home test results

        // Each of these reports a kit's readout rather than an analyte: the ovulation type spans two
        // hormones and the other two are qualitative kit outcomes, so no single LOINC term fits.
        addMapping(for: .ovulationTestResult, category: .laboratoryCategory)
        addMapping(for: .pregnancyTestResult, category: .laboratoryCategory)
        addMapping(for: .progesteroneTestResult, category: .laboratoryCategory)

        // MARK: Cycle tracking

        addMapping(for: .persistentIntermenstrualBleeding, category: .surveyCategory)
        addMapping(for: .prolongedMenstrualPeriods, category: .surveyCategory)
        addMapping(for: .cervicalMucusQuality, category: .surveyCategory, snomed: "251647009", "Cervical mucus consistency")
        addMapping(for: .infrequentMenstrualCycles, category: .surveyCategory, snomed: "52073004", "Oligomenorrhea")
        addMapping(for: .intermenstrualBleeding, category: .surveyCategory, snomed: "237130006", "Intermenstrual bleeding")
        addMapping(for: .irregularMenstrualCycles, category: .surveyCategory, snomed: "80182007", "Irregular periods")
        addMapping(for: .menstrualFlow, category: .surveyCategory, snomed: "248957007", "Menstrual flow")

        // MARK: Self-reported symptoms

        addMapping(for: .abdominalCramps, category: .surveyCategory)
        addMapping(for: .chestTightnessOrPain, category: .surveyCategory)
        addMapping(for: .hotFlashes, category: .surveyCategory)
        addMapping(for: .moodChanges, category: .surveyCategory)
        addMapping(for: .sleepChanges, category: .surveyCategory)
        addMapping(for: .acne, category: .surveyCategory, snomed: "11381005", "Acne")
        addMapping(for: .appetiteChanges, category: .surveyCategory, snomed: "249473004", "Altered appetite")
        addMapping(for: .bladderIncontinence, category: .surveyCategory, snomed: "165232002", "Urinary incontinence")
        addMapping(for: .bloating, category: .surveyCategory, snomed: "116289008", "Abdominal bloating")
        addMapping(for: .breastPain, category: .surveyCategory, snomed: "53430007", "Pain of breast")
        addMapping(for: .chills, category: .surveyCategory, snomed: "43724002", "Chill")
        addMapping(for: .constipation, category: .surveyCategory, snomed: "14760008", "Constipation")
        addMapping(for: .coughing, category: .surveyCategory, snomed: "49727002", "Cough")
        addMapping(for: .diarrhea, category: .surveyCategory, snomed: "62315008", "Diarrhea")
        addMapping(for: .dizziness, category: .surveyCategory, snomed: "404640003", "Dizziness")
        addMapping(for: .drySkin, category: .surveyCategory, snomed: "52475004", "Dry skin")
        addMapping(for: .fainting, category: .surveyCategory, snomed: "271594007", "Syncope")
        addMapping(for: .fatigue, category: .surveyCategory, snomed: "84229001", "Fatigue")
        addMapping(for: .fever, category: .surveyCategory, snomed: "386661006", "Fever")
        addMapping(for: .generalizedBodyAche, category: .surveyCategory, snomed: "82991003", "Generalized aches and pains")
        addMapping(for: .hairLoss, category: .surveyCategory, snomed: "278040002", "Loss of hair")
        addMapping(for: .headache, category: .surveyCategory, snomed: "25064002", "Headache")
        addMapping(for: .heartburn, category: .surveyCategory, snomed: "16331000", "Heartburn")
        addMapping(for: .lossOfSmell, category: .surveyCategory, snomed: "44169009", "Loss of sense of smell")
        addMapping(for: .lossOfTaste, category: .surveyCategory, snomed: "36955009", "Loss of taste")
        addMapping(for: .lowerBackPain, category: .surveyCategory, snomed: "279039007", "Low back pain")
        addMapping(for: .memoryLapse, category: .surveyCategory, snomed: "225038006", "Memory lapses")
        addMapping(for: .nausea, category: .surveyCategory, snomed: "422587007", "Nausea")
        addMapping(for: .nightSweats, category: .surveyCategory, snomed: "42984000", "Night sweats")
        addMapping(for: .pelvicPain, category: .surveyCategory, snomed: "30473006", "Pain in pelvis")
        addMapping(for: .rapidPoundingOrFlutteringHeartbeat, category: .surveyCategory, snomed: "80313002", "Palpitations")
        addMapping(for: .runnyNose, category: .surveyCategory, snomed: "64531003", "Nasal discharge")
        addMapping(for: .shortnessOfBreath, category: .surveyCategory, snomed: "267036007", "Dyspnea")
        addMapping(for: .sinusCongestion, category: .surveyCategory, snomed: "82297005", "Congestion of nasal sinus")
        addMapping(for: .skippedHeartbeat, category: .surveyCategory, snomed: "248629002", "Pulse missed beats")
        addMapping(for: .soreThroat, category: .surveyCategory, snomed: "267102003", "Sore throat")
        addMapping(for: .vaginalDryness, category: .surveyCategory, snomed: "31908003", "Vaginal dryness")
        addMapping(for: .vomiting, category: .surveyCategory, snomed: "422400008", "Vomiting")
        addMapping(for: .wheezing, category: .surveyCategory, snomed: "56018004", "Wheezing")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .bleedingAfterPregnancy, category: .surveyCategory)
            addMapping(for: .bleedingDuringPregnancy, category: .surveyCategory)
            addMapping(for: .sleepApneaEvent, category: .activityCategory)
        }
        return mapping
    }()
}
