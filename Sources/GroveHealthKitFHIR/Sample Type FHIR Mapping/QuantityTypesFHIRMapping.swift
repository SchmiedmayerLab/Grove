//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length file_types_order

public import GroveHealthKit
public import ModelsR4


/// Controls how `HKQuantitySample`s are mapped into FHIR Observations.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias QuantityTypesFHIRMapping = [SampleType<HKQuantitySample>: QuantityTypeFHIRMapping]


/// Controls how an `HKQuantitySample` is mapped into a FHIR Observation.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(codings:categories:unit:)``
///
/// ### Instance Properties
/// - ``codings``
/// - ``unit``
/// - ``categories``
///
/// ### Supporting Types
/// - ``Unit``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct QuantityTypeFHIRMapping: Sendable {
    /// Defines the unit used by the observation's quantity.
    public struct Unit: Sendable {
        /// The `HKUnit` to use when obtaining the `HKQuantitySample`'s value.
        public let hkUnit: HKUnit
        /// Human-displayable unit string. Must represent the same unit as ``hkUnit``.
        public let unit: String
        /// Code system used by ``code`` (e.g., UCUM)
        public let system: FHIRPrimitive<FHIRURI>?
        /// Coded unit, in ``system``
        public let code: FHIRPrimitive<FHIRString>?
        
        fileprivate init(hkUnit: HKUnit, unit: String, system: FHIRPrimitive<FHIRURI>?, code: FHIRPrimitive<FHIRString>?) {
            assert((system == nil) == (code == nil))
            self.hkUnit = hkUnit
            self.unit = unit
            self.system = system
            self.code = code
        }
        
        public init(hkUnit: HKUnit, unit: String) {
            self.hkUnit = hkUnit
            self.unit = unit
            self.system = nil
            self.code = nil
        }
        
        public init(hkUnit: HKUnit, unit: String, system: FHIRPrimitive<FHIRURI>, code: FHIRPrimitive<FHIRString>) {
            self.hkUnit = hkUnit
            self.unit = unit
            self.system = system
            self.code = code
        }
    }
    
    /// The FHIR `Coding`s to include in the resulting FHIR `Observation`.
    ///
    /// These codings will be appended to `code.coding` within the `Observation`.
    public let codings: [Coding]
    /// The FHIR `Coding`s to set as the resulting FHIR `Observation`'s `category`.
    ///
    /// Each coding is wrapped in its own `CodeableConcept` and appended to the `Observation`'s `category`.
    public let categories: [Coding]
    /// Controls how the resulting FHIR `Observation`'s quantity is constructed.
    public let unit: Unit
    
    public init(codings: [Coding], categories: [Coding] = [], unit: Unit) {
        self.codings = codings
        self.categories = categories
        self.unit = unit
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRPrimitive<FHIRURI> {
    // swiftlint:disable force_unwrapping
    internal static let loincSystem: Self = "http://loinc.org".asFHIRURIPrimitive()!
    internal static let snomedCT: Self = "http://snomed.info/sct".asFHIRURIPrimitive()!
    internal static let unitsOfMeasureSystem: Self = "http://unitsofmeasure.org".asFHIRURIPrimitive()!
    /// HealthKit sample-type identifiers, published as a Grove code system:
    /// Apple's documentation URL is documentation, not terminology.
    internal static let healthKitSystem: Self = GroveFHIRVocabulary.healthKitSampleType
    internal static let observationCategorySystem: Self = "http://terminology.hl7.org/CodeSystem/observation-category".asFHIRURIPrimitive()!
    // swiftlint:enable force_unwrapping
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Coding {
    /// The `vital-signs` category. FHIR's vital-signs profile requires it on every
    /// observation whose code is in the vital-signs list.
    internal static let vitalSignsCategory = Coding(
        code: "vital-signs",
        display: "Vital Signs".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `activity` category, for observations measuring physical activity.
    internal static let activityCategory = Coding(
        code: "activity",
        display: "Activity".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `laboratory` category, for analytes measured from a specimen.
    internal static let laboratoryCategory = Coding(
        code: "laboratory",
        display: "Laboratory".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `procedure` category, for results a performed maneuver produces.
    internal static let procedureCategory = Coding(
        code: "procedure",
        display: "Procedure".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `exam` category, for body measurements and gait assessments outside the vital-signs list.
    internal static let examCategory = Coding(
        code: "exam",
        display: "Exam".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `survey` category, for what the user reports about themselves rather than what a sensor read.
    internal static let surveyCategory = Coding(
        code: "survey",
        display: "Survey".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )

    /// The `social-history` category, for lifestyle, reproductive history and environmental exposure.
    internal static let socialHistoryCategory = Coding(
        code: "social-history",
        display: "Social History".asFHIRStringPrimitive(),
        system: .observationCategorySystem
    )
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Coding {
    init(_ sampleType: SampleType<HKQuantitySample>) {
        self.init(
            code: sampleType.identifier.rawValue.asFHIRStringPrimitive(),
            display: sampleType.canonicalTitle.asFHIRStringPrimitive(),
            system: .healthKitSystem
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuantityTypesFHIRMapping {
    /// The default FHIR mapping for HealthKit Quantity types
    public static let `default`: Self = { // swiftlint:disable:this closure_body_length
        // NOTE: for all of the entries here, it is important that the UCUM unit (the `code` param in the `addMapping` function) be equivalent to the sample type's canonical healthkit unit.
        // UCUM annotations name the thing counted in the singular ({flight}, {stroke}, {puff}); `{steps}` is the
        // one exception, kept plural because it is already published in the guide's step-count example.
        // `categories` follows the observed concept, not the sample's provenance: `activity` for what the body did,
        // `laboratory` for specimen analytes, `procedure` for the result of a maneuver, `exam` for body
        // measurements and gait assessments. `vital-signs` is reserved for the codes FHIR's vital-signs profile
        // lists, since writing it pulls that profile in.
        var mapping: Self = [:]
        /// Adds an entry to the mapping being built up
        ///
        /// - parameter sampleType: The `SampleType<HKQuantitySample>` to which the entry belongs
        /// - parameter extraCodings: Additional FHIR `Coding`s to add
        /// - parameter categories: FHIR categories to add
        /// - parameter unitString: Human-readable representation of the unit.
        ///     Must be semantically equivalent to `sampleType.canonicalUnit`.
        ///     Exists as a separate input to allow a `HKUnit.count()`-based sample type such as e.g. floorsClimbed to instead use "floors" as its human-readable unit.
        func addMapping(
            for sampleType: SampleType<HKQuantitySample>,
            extraCodings: [Coding] = [],
            categories: [Coding] = [],
            unitString: String,
            system: FHIRPrimitive<FHIRURI>?,
            code: FHIRPrimitive<FHIRString>?
        ) {
            assert((system == nil) == (code == nil))
            assert(mapping[sampleType] == nil, "Sample Type '\(sampleType)' already has an entry!")
            mapping[sampleType] = QuantityTypeFHIRMapping(
                codings: extraCodings + [Coding(sampleType)],
                categories: categories,
                unit: QuantityTypeFHIRMapping.Unit(
                    hkUnit: sampleType.canonicalUnit,
                    unit: unitString,
                    system: system,
                    code: code
                )
            )
        }
        addMapping(
            for: .activeEnergyBurned,
            extraCodings: [
                Coding(
                    code: "41981-2",
                    display: "Calories burned",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "kcal",
            system: .unitsOfMeasureSystem,
            code: "kcal"
        )
        addMapping(for: .appleExerciseTime, categories: [.activityCategory], unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        addMapping(for: .appleMoveTime, categories: [.activityCategory], unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .appleSleepingBreathingDisturbances, unitString: "count", system: .unitsOfMeasureSystem, code: "{count}")
        }
        addMapping(for: .appleSleepingWristTemperature, unitString: "C", system: .unitsOfMeasureSystem, code: "Cel")
        addMapping(for: .appleStandTime, categories: [.activityCategory], unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        addMapping(for: .appleWalkingSteadiness, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(for: .atrialFibrillationBurden, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(
            for: .basalBodyTemperature,
            extraCodings: [
                Coding(
                    code: "8310-5",
                    display: "Body temperature",
                    system: .loincSystem
                ),
                Coding(
                    code: "300076005",
                    display: "Basal body temperature",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "C",
            system: .unitsOfMeasureSystem,
            code: "Cel"
        )
        addMapping(
            for: .basalEnergyBurned,
            extraCodings: [
                // Not LOINC 41981-2: that is the active burn, already on `activeEnergyBurned`, and reusing
                // it here would collapse the two into one concept.
                Coding(
                    code: "1285369003",
                    display: "Resting energy expenditure",
                    system: .snomedCT
                )
            ],
            categories: [.activityCategory],
            unitString: "kcal",
            system: .unitsOfMeasureSystem,
            code: "kcal"
        )
        addMapping(
            for: .bloodAlcoholContent,
            extraCodings: [
                Coding(
                    code: "74859-0", // 5640-8?
                    display: "Ethanol [Mass/volume] in Blood Estimated from serum or plasma level",
                    system: .loincSystem
                )
            ],
            categories: [.laboratoryCategory],
            unitString: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
        addMapping(
            for: .bloodGlucose,
            extraCodings: [
                Coding(
                    code: "2339-0",
                    display: "Glucose [Mass/volume] in Blood",
                    system: .loincSystem
                )
            ],
            categories: [.laboratoryCategory],
            unitString: "mg/dL",
            system: .unitsOfMeasureSystem,
            code: "mg/dL"
        )
        addMapping(
            for: .bloodPressureDiastolic,
            extraCodings: [
                Coding(
                    code: "8462-4",
                    display: "Diastolic blood pressure",
                    system: .loincSystem
                ),
                Coding(
                    code: "271650006",
                    display: "Diastolic blood pressure",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "mmHg",
            system: .unitsOfMeasureSystem,
            code: "mm[Hg]"
        )
        addMapping(
            for: .bloodPressureSystolic,
            extraCodings: [
                Coding(
                    code: "8480-6",
                    display: "Systolic blood pressure",
                    system: .loincSystem
                ),
                Coding(
                    code: "271649006",
                    display: "Systolic blood pressure",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "mmHg",
            system: .unitsOfMeasureSystem,
            code: "mm[Hg]"
        )
        addMapping(
            for: .bodyFatPercentage,
            extraCodings: [
                Coding(
                    code: "41982-0",
                    display: "Percentage of body fat Measured",
                    system: .loincSystem
                )
            ],
            categories: [.examCategory],
            unitString: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
        addMapping(
            for: .bodyMass,
            extraCodings: [
                Coding(
                    code: "29463-7",
                    display: "Body weight",
                    system: .loincSystem
                ),
                Coding(
                    code: "27113001",
                    display: "Body weight",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "kg",
            system: .unitsOfMeasureSystem,
            code: "kg"
        )
        addMapping(
            for: .bodyMassIndex,
            extraCodings: [
                Coding(
                    code: "39156-5",
                    display: "Body mass index (BMI) [Ratio]",
                    system: .loincSystem
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "kg/m^2",
            system: .unitsOfMeasureSystem,
            code: "kg/m2"
        )
        addMapping(
            for: .bodyTemperature,
            extraCodings: [
                Coding(
                    code: "8310-5",
                    display: "Body temperature",
                    system: .loincSystem
                ),
                Coding(
                    code: "386725007",
                    display: "Body temperature",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "C",
            system: .unitsOfMeasureSystem,
            code: "Cel"
        )
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(
                for: .crossCountrySkiingSpeed,
                unitString: "m/s",
                system: .unitsOfMeasureSystem,
                code: "m/s"
            )
        }
        addMapping(
            for: .cyclingCadence,
            unitString: "r/min",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
        addMapping(
            for: .cyclingFunctionalThresholdPower,
            unitString: "watt",
            system: .unitsOfMeasureSystem,
            code: "W"
        )
        addMapping(
            for: .cyclingPower,
            unitString: "watt",
            system: .unitsOfMeasureSystem,
            code: "W"
        )
        addMapping(
            for: .cyclingSpeed,
            unitString: "m/s",
            system: .unitsOfMeasureSystem,
            code: "m/s"
        )
        do {
            let byUnit: [String: [SampleType<HKQuantitySample>]] = [
                // swiftlint:disable line_length
                "ug": [.dietaryBiotin, .dietaryChromium, .dietaryCopper, .dietaryFolate, .dietaryIodine, .dietaryMolybdenum, .dietarySelenium, .dietaryVitaminA, .dietaryVitaminB12, .dietaryVitaminD, .dietaryVitaminK],
                "mg": [.dietaryCaffeine, .dietaryCalcium, .dietaryChloride, .dietaryCholesterol, .dietaryIron, .dietaryMagnesium, .dietaryManganese, .dietaryNiacin, .dietaryPantothenicAcid, .dietaryPhosphorus, .dietaryPotassium, .dietaryRiboflavin, .dietarySodium, .dietaryThiamin, .dietaryVitaminB6, .dietaryVitaminC, .dietaryVitaminE, .dietaryZinc],
                "g": [.dietaryCarbohydrates, .dietaryFatMonounsaturated, .dietaryFatPolyunsaturated, .dietaryFatSaturated, .dietaryFatTotal, .dietaryProtein, .dietarySugar]
                // swiftlint:enable line_length
            ]
            // SNOMED CT's nutrient-intake observables fix neither a period nor a method, which is what a
            // per-logging-event sample needs. LOINC's intake terms do one or the other — a 24-hour total,
            // or an "Estimated"/"Measured" method HealthKit does not record — so none of them apply here.
            // Chloride, cholesterol and total fat have no term free of both, and keep the identifier alone.
            let intakeConcepts: [SampleType<HKQuantitySample>: (code: FHIRPrimitive<FHIRString>, display: FHIRPrimitive<FHIRString>)] = [
                .dietaryBiotin: ("700183008", "Biotin intake"),
                .dietaryCaffeine: ("1208604004", "Caffeine intake"),
                .dietaryCalcium: ("230122008", "Calcium intake"),
                .dietaryCarbohydrates: ("788472008", "Carbohydrate intake"),
                .dietaryChromium: ("890196009", "Chromium intake"),
                .dietaryCopper: ("286615007", "Copper intake"),
                .dietaryFatMonounsaturated: ("226329008", "Monounsaturated fat intake"),
                .dietaryFatPolyunsaturated: ("226330003", "Polyunsaturated fat intake"),
                .dietaryFatSaturated: ("226328000", "Saturated fat intake"),
                .dietaryFolate: ("792806007", "Folate and/or folate derivative intake"),
                .dietaryIodine: ("890199002", "Iodine intake"),
                .dietaryIron: ("286614006", "Iron intake"),
                .dietaryMagnesium: ("230124009", "Magnesium intake"),
                .dietaryManganese: ("890198005", "Manganese intake"),
                .dietaryMolybdenum: ("890200004", "Molybdenum intake"),
                .dietaryNiacin: ("286583002", "Niacin intake"),
                .dietaryPantothenicAcid: ("286600006", "Pantothenic acid intake"),
                .dietaryPhosphorus: ("230123003", "Phosphorus intake"),
                .dietaryPotassium: ("788479004", "Potassium intake"),
                .dietaryProtein: ("874875003", "Protein and/or protein derivative intake"),
                .dietaryRiboflavin: ("286581000", "Vitamin B2 intake"),
                .dietarySelenium: ("286616008", "Selenium intake"),
                .dietarySodium: ("1148504005", "Sodium intake"),
                .dietarySugar: ("226459004", "Sugar intake"),
                .dietaryThiamin: ("286579002", "Vitamin B1 intake"),
                .dietaryVitaminA: ("286604002", "Vitamin A intake"),
                .dietaryVitaminB12: ("1144896002", "Vitamin B12 and/or vitamin B12 derivative intake"),
                .dietaryVitaminB6: ("1144810007", "Vitamin B6 and/or vitamin B6 derivative intake"),
                .dietaryVitaminC: ("286586005", "Vitamin C intake"),
                .dietaryVitaminD: ("286607009", "Vitamin D intake"),
                .dietaryVitaminE: ("286606000", "Vitamin E intake"),
                .dietaryVitaminK: ("430195004", "Vitamin K intake"),
                .dietaryZinc: ("286617004", "Zinc intake")
            ]
            for (unit, sampleTypes) in byUnit {
                for sampleType in sampleTypes {
                    addMapping(
                        for: sampleType,
                        extraCodings: intakeConcepts[sampleType].map { [Coding(code: $0.code, display: $0.display, system: .snomedCT)] } ?? [],
                        unitString: unit,
                        system: .unitsOfMeasureSystem,
                        code: unit.asFHIRStringPrimitive()
                    )
                }
            }
        }
        
        addMapping(
            for: .dietaryEnergyConsumed,
            extraCodings: [
                Coding(
                    code: "9052-2",
                    display: "Calorie intake total",
                    system: .loincSystem
                ),
                Coding(
                    code: "787787004",
                    display: "Energy intake",
                    system: .snomedCT
                )
            ],
            unitString: "kcal",
            system: .unitsOfMeasureSystem,
            code: "kcal"
        )
        // No LOINC coding: every fiber-intake term LOINC publishes is a 24-hour total in g/(24.h)
        // (81133-1, 81057-2 and the soluble/insoluble pairs), which contradicts a per-logging-event
        // mass sample. SNOMED's plant-fiber intake is the total the soluble and insoluble terms sit under.
        addMapping(
            for: .dietaryFiber,
            extraCodings: [
                Coding(
                    code: "876831004",
                    display: "Plant fiber intake",
                    system: .snomedCT
                )
            ],
            unitString: "g",
            system: .unitsOfMeasureSystem,
            code: "g"
        )

        addMapping(
            for: .dietaryWater,
            extraCodings: [
                Coding(
                    code: "8999-5",
                    display: "Fluid intake oral Estimated",
                    system: .loincSystem
                ),
                Coding(
                    code: "226354008",
                    display: "Water intake",
                    system: .snomedCT
                )
            ],
            unitString: "L",
            system: .unitsOfMeasureSystem,
            code: "L"
        )
        
        do {
            var sampleTypes: [SampleType<HKQuantitySample>] = [
                .distanceCycling, .distanceDownhillSnowSports
            ]
            if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
                sampleTypes += [
                    .distanceCrossCountrySkiing,
                    .distancePaddleSports,
                    .distanceRowing,
                    .distanceSkatingSports
                ]
            }
            for sampleType in sampleTypes {
                addMapping(for: sampleType, categories: [.activityCategory], unitString: "m", system: .unitsOfMeasureSystem, code: "m")
            }
        }
        addMapping(
            for: .distanceSwimming,
            extraCodings: [
                Coding(
                    code: "93816-7",
                    display: "Swimming distance unspecified time",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        // The Pedometer method is kept deliberately: LOINC's only unspecified-time walking-distance term
        // carries it, and the method-neutral alternatives (41953-1, 41954-9) are 24-hour aggregates,
        // which contradicts a sample covering an arbitrary interval.
        addMapping(
            for: .distanceWalkingRunning,
            extraCodings: [
                Coding(
                    code: "55430-3",
                    display: "Walking distance unspecified time Pedometer",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        addMapping(
            for: .distanceWheelchair,
            extraCodings: [
                // ???
            ],
            categories: [.activityCategory],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        
        addMapping(for: .electrodermalActivity, unitString: "microsiemens", system: .unitsOfMeasureSystem, code: "uS")
        // HealthKit measures these in dBASPL and UCUM has no A-weighted bel, so the weighting is carried as
        // an annotation. Sound reduction is an attenuation, i.e. a ratio, so it takes plain `dB` rather than
        // `dB[SPL]`, which is an absolute level referenced to 20 uPa.
        addMapping(for: .environmentalAudioExposure, unitString: "dB(A) SPL", system: .unitsOfMeasureSystem, code: "dB[SPL]{A}")
        addMapping(for: .environmentalSoundReduction, unitString: "dB(A)", system: .unitsOfMeasureSystem, code: "dB{A}")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .estimatedWorkoutEffortScore, unitString: "effort", system: .unitsOfMeasureSystem, code: "{score}")
        }
        addMapping(for: .heartRateRecoveryOneMinute, unitString: "beats/minute", system: .unitsOfMeasureSystem, code: "/min")
        addMapping(
            for: .flightsClimbed,
            extraCodings: [
                Coding(
                    code: "100304-5",
                    display: "Flights climbed [#] Reporting Period",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "flights",
            system: .unitsOfMeasureSystem,
            code: "{flight}"
        )
        addMapping(
            for: .forcedExpiratoryVolume1,
            extraCodings: [
                Coding(
                    code: "20150-9",
                    display: "FEV1",
                    system: .loincSystem
                )
            ],
            categories: [.procedureCategory],
            unitString: "L",
            system: .unitsOfMeasureSystem,
            code: "L"
        )
        addMapping(
            for: .forcedVitalCapacity,
            extraCodings: [
                Coding(
                    code: "19870-5",
                    display: "Forced vital capacity [Volume] Respiratory system",
                    system: .loincSystem
                )
            ],
            categories: [.procedureCategory],
            unitString: "L",
            system: .unitsOfMeasureSystem,
            code: "L"
        )
        addMapping(for: .headphoneAudioExposure, unitString: "dB(A) SPL", system: .unitsOfMeasureSystem, code: "dB[SPL]{A}")
        addMapping(
            for: .heartRate,
            extraCodings: [
                Coding(
                    code: "8867-4",
                    display: "Heart rate",
                    system: .loincSystem
                ),
                Coding(
                    code: "364075005",
                    display: "Heart rate",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "beats/minute",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
        addMapping(
            for: .heartRateVariabilitySDNN,
            extraCodings: [
                Coding(
                    code: "80404-7",
                    display: "R-R interval.standard deviation (Heart rate variability)",
                    system: .loincSystem
                )
            ],
            unitString: "ms",
            system: .unitsOfMeasureSystem,
            code: "ms"
        )
        addMapping(
            for: .height,
            extraCodings: [
                Coding(
                    code: "8302-2",
                    display: "Body height",
                    system: .loincSystem
                ),
                Coding(
                    code: "50373000",
                    display: "Body height measure",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "cm",
            system: .unitsOfMeasureSystem,
            code: "cm"
        )
        addMapping(for: .inhalerUsage, unitString: "puffs", system: .unitsOfMeasureSystem, code: "{puff}")
        // `[iU]` is UCUM's case-sensitive code for the international unit; "IU" is that unit's print symbol.
        addMapping(for: .insulinDelivery, unitString: "IU", system: .unitsOfMeasureSystem, code: "[iU]")
        addMapping(
            for: .leanBodyMass,
            extraCodings: [
                Coding(
                    code: "91557-9",
                    display: "Lean body weight",
                    system: .loincSystem
                )
            ],
            categories: [.examCategory],
            unitString: "kg",
            system: .unitsOfMeasureSystem,
            code: "kg"
        )
        addMapping(for: .nikeFuel, unitString: "nikeFuel", system: nil, code: nil)
        addMapping(for: .numberOfAlcoholicBeverages, unitString: "beverages", system: .unitsOfMeasureSystem, code: "{beverage}")
        addMapping(
            for: .numberOfTimesFallen,
            extraCodings: [
                // LOINC's fall counts all fix a lookback window (12 months, 3 months, since admission);
                // the SNOMED observable counts falls over whatever period the sample covers.
                Coding(
                    code: "298348009",
                    display: "Number of falls",
                    system: .snomedCT
                )
            ],
            unitString: "falls",
            system: .unitsOfMeasureSystem,
            code: "{fall}"
        )
        addMapping(
            for: .bloodOxygen,
            extraCodings: [
                // 2708-6 is the vital-signs "magic value"; 59408-5 records the pulse-oximetry method.
                Coding(
                    code: "2708-6",
                    display: "Oxygen saturation in Arterial blood",
                    system: .loincSystem
                ),
                Coding(
                    code: "59408-5",
                    display: "Oxygen saturation in Arterial blood by Pulse oximetry",
                    system: .loincSystem
                ),
                Coding(
                    code: "431314004",
                    display: "Peripheral oxygen saturation",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .paddleSportsSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        }
        addMapping(
            for: .peakExpiratoryFlowRate,
            extraCodings: [
                Coding(
                    code: "33452-4",
                    display: "Maximum expiratory gas flow Respiratory system airway",
                    system: .loincSystem
                )
            ],
            categories: [.procedureCategory],
            unitString: "L/min",
            system: .unitsOfMeasureSystem,
            code: "L/min"
        )
        addMapping(
            for: .peripheralPerfusionIndex,
            extraCodings: [
                Coding(
                    code: "61006-3",
                    display: "Perfusion index Tissue by Pulse oximetry",
                    system: .loincSystem
                )
            ],
            unitString: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
        addMapping(for: .physicalEffort, unitString: "kcal/(kg.h)", system: .unitsOfMeasureSystem, code: "kcal/(kg.h)")
        addMapping(
            for: .pushCount,
            extraCodings: [
                Coding(
                    code: "96502-0",
                    display: "Number of wheelchair pushes per time period",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "wheelchair pushes",
            system: .unitsOfMeasureSystem,
            code: "{wheelchair-push}"
        )
        addMapping(
            for: .respiratoryRate,
            extraCodings: [
                Coding(
                    code: "9279-1",
                    display: "Respiratory rate",
                    system: .loincSystem
                ),
                Coding(
                    code: "86290005",
                    display: "Respiratory rate",
                    system: .snomedCT
                )
            ],
            categories: [.vitalSignsCategory],
            unitString: "breaths/minute",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
        addMapping(
            for: .restingHeartRate,
            extraCodings: [
                Coding(
                    code: "40443-4",
                    display: "Heart rate --resting",
                    system: .loincSystem
                )
            ],
            unitString: "beats/minute",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .rowingSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        }
        addMapping(for: .runningGroundContactTime, unitString: "ms", system: .unitsOfMeasureSystem, code: "ms")
        addMapping(for: .runningPower, unitString: "watt", system: .unitsOfMeasureSystem, code: "W")
        addMapping(for: .runningSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        addMapping(for: .runningStrideLength, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
        addMapping(for: .runningVerticalOscillation, unitString: "cm", system: .unitsOfMeasureSystem, code: "cm")
        addMapping(
            for: .sixMinuteWalkTestDistance,
            extraCodings: [
                Coding(
                    code: "64098-7",
                    display: "Six minute walk test",
                    system: .loincSystem
                )
            ],
            categories: [.examCategory],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        addMapping(for: .stairAscentSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        addMapping(for: .stairDescentSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        // As for walking distance, the Pedometer method is the only unspecified-time steps term LOINC has,
        // and it does describe how the device counts: 41950-7 and 41952-3 are 24-hour and weekly aggregates.
        addMapping(
            for: .stepCount,
            extraCodings: [
                Coding(
                    code: "55423-8",
                    display: "Number of steps in unspecified time Pedometer",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "steps",
            system: .unitsOfMeasureSystem,
            code: "{steps}"
        )
        addMapping(for: .swimmingStrokeCount, categories: [.activityCategory], unitString: "strokes", system: .unitsOfMeasureSystem, code: "{stroke}")
        addMapping(for: .timeInDaylight, unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        addMapping(for: .underwaterDepth, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
        addMapping(for: .uvExposure, unitString: "count", system: .unitsOfMeasureSystem, code: "{count}")
        // 60842-2 is a plain volume rate in mL/min; HealthKit's VO2max is weight-indexed, which is what
        // 94122-9 codes, down to the `{body_wt}` annotation on its example units.
        addMapping(
            for: .vo2Max,
            extraCodings: [
                Coding(
                    code: "94122-9",
                    display: "Oxygen consumption (VO2)/Body weight [Volume Rate Content] --peak during exercise",
                    system: .loincSystem
                )
            ],
            categories: [.activityCategory],
            unitString: "mL/kg/min",
            system: .unitsOfMeasureSystem,
            code: "mL/min/kg{body_wt}"
        )
        // No LOINC coding: every waist-circumference term LOINC publishes fixes a method, and 8280-0 fixes an
        // umbilicus landmark on top of it. HealthKit records neither, so only the method-free SNOMED term applies.
        addMapping(
            for: .waistCircumference,
            extraCodings: [
                Coding(
                    code: "276361009",
                    display: "Waist circumference",
                    system: .snomedCT
                )
            ],
            categories: [.examCategory],
            unitString: "cm",
            system: .unitsOfMeasureSystem,
            code: "cm"
        )
        addMapping(for: .walkingAsymmetryPercentage, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(for: .walkingDoubleSupportPercentage, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(for: .walkingHeartRateAverage, unitString: "beats/minute", system: .unitsOfMeasureSystem, code: "/min")
        // LOINC's walking-speed terms are all 24-hour or weekly means and maxima; SNOMED's gait speed is
        // the plain observable, which is what a single mobility sample carries.
        addMapping(
            for: .walkingSpeed,
            extraCodings: [
                Coding(
                    code: "724237005",
                    display: "Gait speed",
                    system: .snomedCT
                )
            ],
            categories: [.examCategory],
            unitString: "m/s",
            system: .unitsOfMeasureSystem,
            code: "m/s"
        )
        addMapping(for: .walkingStepLength, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
        addMapping(for: .waterTemperature, unitString: "C", system: .unitsOfMeasureSystem, code: "Cel")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .workoutEffortScore, unitString: "effort", system: .unitsOfMeasureSystem, code: "{score}")
        }
        return mapping
    }()
}
