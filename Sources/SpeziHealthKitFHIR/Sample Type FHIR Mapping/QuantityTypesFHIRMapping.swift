//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length file_types_order

public import ModelsR4
public import SpeziHealthKit


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
    internal static let healthKitSystem: Self = "http://developer.apple.com/documentation/healthkit".asFHIRURIPrimitive()!
    // swiftlint:enable force_unwrapping
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
        var mapping: Self = [:]
        func addMapping(
            for sampleType: SampleType<HKQuantitySample>,
            extraCodings: [Coding] = [],
            case categories: [Coding] = [],
            unitString: String,
            system: FHIRPrimitive<FHIRURI>?,
            code: FHIRPrimitive<FHIRString>?
        ) {
            assert((system == nil) == (code == nil))
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
            unitString: "kcal",
            system: .unitsOfMeasureSystem,
            code: "kcal"
        )
        addMapping(for: .appleExerciseTime, unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        addMapping(for: .appleMoveTime, unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .appleSleepingBreathingDisturbances, unitString: "count", system: nil, code: nil)
        }
        addMapping(for: .appleSleepingWristTemperature, unitString: "C", system: .unitsOfMeasureSystem, code: "Cel")
        addMapping(for: .appleStandTime, unitString: "min", system: .unitsOfMeasureSystem, code: "min")
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
                    system: .snomedCT
                )
            ],
            unitString: "C",
            system: .unitsOfMeasureSystem,
            code: "Cel"
        )
        addMapping(for: .basalEnergyBurned, unitString: "kcal", system: .unitsOfMeasureSystem, code: "kcal")
        addMapping(
            for: .bloodAlcoholContent,
            extraCodings: [
                Coding(
                    code: "74859-0", // 5640-8?
                    display: "Ethanol [Mass/volume] in Blood Estimated from serum or plasma level",
                    system: .loincSystem
                )
            ],
            unitString: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
        addMapping(
            for: .bloodGlucose,
            extraCodings: [
                Coding(
                    code: "41653-7",
                    display: "Glucose Glucometer (BldC) [Mass/Vol]",
                    system: .loincSystem
                )
            ],
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
            for (unit, sampleTypes) in byUnit {
                for sampleType in sampleTypes {
                    addMapping(
                        for: sampleType,
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
                )
            ],
            unitString: "kcal",
            system: .unitsOfMeasureSystem,
            code: "kcal"
        )
        addMapping(
            for: .dietaryFiber,
            extraCodings: [
                Coding(
                    code: "LP203183-1",
                    display: "Fiber intake",
                    system: .loincSystem
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
            unitString: "l",
            system: .unitsOfMeasureSystem,
            code: "l"
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
                addMapping(for: sampleType, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
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
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        addMapping(
            for: .distanceWalkingRunning,
            extraCodings: [
                // ???
            ],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        addMapping(
            for: .distanceWheelchair,
            extraCodings: [
                // ???
            ],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        
        addMapping(for: .electrodermalActivity, unitString: "microsiemens", system: .unitsOfMeasureSystem, code: "mcS")
        addMapping(for: .environmentalAudioExposure, unitString: "dB(SPL)", system: .unitsOfMeasureSystem, code: "dB(SPL)")
        addMapping(for: .environmentalSoundReduction, unitString: "dB(HL)", system: .unitsOfMeasureSystem, code: "dB(HL)")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .estimatedWorkoutEffortScore, unitString: "effort", system: nil, code: nil)
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
            unitString: "flights",
            system: nil,
            code: nil
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
            unitString: "L",
            system: .unitsOfMeasureSystem,
            code: "L"
        )
        addMapping(for: .headphoneAudioExposure, unitString: "dB(SPL)", system: .unitsOfMeasureSystem, code: "dB(SPL)")
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
            unitString: "cm",
            system: .unitsOfMeasureSystem,
            code: "cm"
        )
        addMapping(for: .inhalerUsage, unitString: "count", system: nil, code: nil)
        addMapping(for: .insulinDelivery, unitString: "IU", system: .unitsOfMeasureSystem, code: "IU")
        addMapping(
            for: .leanBodyMass,
            extraCodings: [
                Coding(
                    code: "91557-9",
                    display: "Lean body weight",
                    system: .loincSystem
                )
            ],
            unitString: "kg",
            system: .unitsOfMeasureSystem,
            code: "kg"
        )
        addMapping(for: .nikeFuel, unitString: "nikeFuel", system: nil, code: nil)
        addMapping(for: .numberOfAlcoholicBeverages, unitString: "beverages", system: nil, code: nil)
        addMapping(for: .numberOfTimesFallen, unitString: "falls", system: nil, code: nil)
        addMapping(
            for: .bloodOxygen,
            extraCodings: [
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
                    code: "19935-6",
                    display: "Maximum expiratory gas flow Respiratory system airway by Peak flow meter",
                    system: .loincSystem
                )
            ],
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
            unitString: "wheelchair pushes",
            system: nil,
            code: nil
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
                    code: "55430-3",
                    display: "6 minute walk test Distance",
                    system: .loincSystem
                )
            ],
            unitString: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
        addMapping(for: .stairAscentSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        addMapping(for: .stairDescentSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        addMapping(
            for: .stepCount,
            extraCodings: [
                Coding(
                    code: "55423-8",
                    display: "Number of steps in unspecified time Pedometer",
                    system: .loincSystem
                )
            ],
            unitString: "steps",
            system: nil,
            code: nil
        )
        addMapping(for: .swimmingStrokeCount, unitString: "strokes", system: nil, code: nil)
        addMapping(for: .timeInDaylight, unitString: "min", system: .unitsOfMeasureSystem, code: "min")
        addMapping(for: .underwaterDepth, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
        addMapping(for: .uvExposure, unitString: "count", system: nil, code: nil)
        addMapping(for: .vo2Max, unitString: "mL/kg/min", system: .unitsOfMeasureSystem, code: "mL/kg/min")
        addMapping(
            for: .waistCircumference,
            extraCodings: [
                Coding(
                    code: "8280-0",
                    display: "Waist Circumference at umbilicus by Tape measure",
                    system: .loincSystem
                ),
                Coding(
                    code: "276361009",
                    display: "Waist circumference",
                    system: .snomedCT
                )
            ],
            unitString: "cm",
            system: .unitsOfMeasureSystem,
            code: "cm"
        )
        addMapping(for: .walkingAsymmetryPercentage, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(for: .walkingDoubleSupportPercentage, unitString: "%", system: .unitsOfMeasureSystem, code: "%")
        addMapping(for: .walkingHeartRateAverage, unitString: "beats/minute", system: .unitsOfMeasureSystem, code: "/min")
        addMapping(for: .walkingSpeed, unitString: "m/s", system: .unitsOfMeasureSystem, code: "m/s")
        addMapping(for: .walkingStepLength, unitString: "m", system: .unitsOfMeasureSystem, code: "m")
        addMapping(for: .waterTemperature, unitString: "C", system: .unitsOfMeasureSystem, code: "Cel")
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) {
            addMapping(for: .workoutEffortScore, unitString: "effort", system: nil, code: nil)
        }
        return mapping
    }()
}
