//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HKCategorySampleTests {
    var startDate: Date {
        get throws {
            let dateComponents = DateComponents(year: 1891, month: 10, day: 1, hour: 12, minute: 0, second: 0) // Date Stanford University opened (https://www.stanford.edu/about/history/)
            return try #require(Calendar.current.date(from: dateComponents))
        }
    }

    var endDate: Date {
        get throws {
            let dateComponents = DateComponents(year: 1891, month: 10, day: 1, hour: 12, minute: 0, second: 42)
            return try #require(Calendar.current.date(from: dateComponents))
        }
    }

    
    func createObservationFrom(
        type categoryType: HKCategoryTypeIdentifier,
        value: Int,
        metadata: [String: Any] = [:]
    ) throws -> Observation {
        let categorySample = HKCategorySample(
            type: HKCategoryType(categoryType),
            value: value,
            start: try startDate,
            end: try endDate,
            metadata: metadata
        )
        return try #require(categorySample.resource(subject: Reference(reference: "Patient/example")).get(if: Observation.self))
    }

    func createCategoryCoding(
        categoryType: HKCategoryTypeIdentifier,
        display: String
    ) -> Coding {
        Coding(
            code: FHIRPrimitive(stringLiteral: categoryType.rawValue),
            display: FHIRPrimitive(stringLiteral: display),
            system: FHIRPrimitive(FHIRURI(stringLiteral: SupportedCodeSystem.apple.rawValue))
        )
    }

    
    @Test(arguments: [
        (HKCategoryValueCervicalMucusQuality.dry, "dry", "dry"),
        (HKCategoryValueCervicalMucusQuality.sticky, "sticky", "sticky"),
        (HKCategoryValueCervicalMucusQuality.creamy, "creamy", "creamy"),
        (HKCategoryValueCervicalMucusQuality.watery, "watery", "watery"),
        (HKCategoryValueCervicalMucusQuality.eggWhite, "eggWhite", "egg white")
    ])
    func cervicalMucusQuality(value: HKCategoryValueCervicalMucusQuality, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-cervical-mucus-quality"
        let observation = try createObservationFrom(
            type: .cervicalMucusQuality,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .cervicalMucusQuality,
            display: "Cervical Mucus Quality"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ])))
    }

    @Test(arguments: [
        (HKCategoryValueMenstrualFlow.unspecified, "unspecified", "unspecified"),
        (HKCategoryValueMenstrualFlow.light, "light", "light"),
        (HKCategoryValueMenstrualFlow.medium, "medium", "medium"),
        (HKCategoryValueMenstrualFlow.heavy, "heavy", "heavy"),
        (HKCategoryValueMenstrualFlow.none, "none", "none")
    ])
    func menstrualFlow(value: HKCategoryValueMenstrualFlow, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-menstrual-flow"
        let observation = try createObservationFrom(
            type: .menstrualFlow,
            value: value.rawValue,
            metadata: [HKMetadataKeyMenstrualCycleStart: true]
        )
        #expect((observation.code.coding ?? []).contains(createCategoryCoding(
            categoryType: .menstrualFlow,
            display: "Menstrual Flow"
        )))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ])))
    }

    @Test(arguments: [
        (HKCategoryValueOvulationTestResult.negative, "negative", "negative"),
        (HKCategoryValueOvulationTestResult.luteinizingHormoneSurge, "luteinizingHormoneSurge", "luteinizing hormone surge"),
        (HKCategoryValueOvulationTestResult.indeterminate, "indeterminate", "indeterminate"),
        (HKCategoryValueOvulationTestResult.estrogenSurge, "estrogenSurge", "estrogen surge")
    ])
    func ovulationTestResult(value: HKCategoryValueOvulationTestResult, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-ovulation-test-result"
        let observation = try createObservationFrom(
            type: .ovulationTestResult,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .ovulationTestResult,
            display: "Ovulation Test Result"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ])))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        _ = try encoder.encode(observation)
    }

    @Test(arguments: [
        (HKCategoryValueContraceptive.unspecified, "unspecified", "unspecified"),
        (HKCategoryValueContraceptive.implant, "implant", "implant"),
        (HKCategoryValueContraceptive.injection, "injection", "injection"),
        (HKCategoryValueContraceptive.intrauterineDevice, "intrauterineDevice", "intrauterine device"),
        (HKCategoryValueContraceptive.intravaginalRing, "intravaginalRing", "intravaginal ring"),
        (HKCategoryValueContraceptive.oral, "oral", "oral"),
        (HKCategoryValueContraceptive.patch, "patch", "patch")
    ])
    func contraceptive(value: HKCategoryValueContraceptive, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-contraceptive"
        let observation = try createObservationFrom(
            type: .contraceptive,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .contraceptive,
            display: "Contraceptive"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ])))
    }

    @Test(arguments: [
        (HKCategoryValueSleepAnalysis.inBed, "inBed", "in bed"),
        (HKCategoryValueSleepAnalysis.asleepUnspecified, "asleepUnspecified", "asleep unspecified"),
        (HKCategoryValueSleepAnalysis.awake, "awake", "awake"),
        (HKCategoryValueSleepAnalysis.asleepCore, "asleepCore", "asleep core"),
        (HKCategoryValueSleepAnalysis.asleepDeep, "asleepDeep", "asleep deep"),
        (HKCategoryValueSleepAnalysis.asleepREM, "asleepREM", "asleep REM")
    ])
    func sleepAnalysis(value: HKCategoryValueSleepAnalysis, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-sleep-analysis"
        let observation = try createObservationFrom(
            type: .sleepAnalysis,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .sleepAnalysis,
            display: "Sleep Analysis"
        ))
        // The HealthKit stage coding, plus a parallel LOINC stage code where one exists.
        let loinc: Coding? = switch value {
        case .inBed, .asleepUnspecified:
            Coding(code: "93832-4", display: "Sleep duration".asFHIRStringPrimitive(), system: "http://loinc.org")
        case .asleepREM:
            Coding(code: "93829-0", display: "REM sleep duration".asFHIRStringPrimitive(), system: "http://loinc.org")
        case .asleepCore:
            Coding(code: "93830-8", display: "Light sleep duration".asFHIRStringPrimitive(), system: "http://loinc.org")
        case .asleepDeep:
            Coding(code: "93831-6", display: "Deep sleep duration".asFHIRStringPrimitive(), system: "http://loinc.org")
        default:
            nil
        }
        let expected = [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ] + (loinc.map { [$0] } ?? [])
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: expected)))
    }

    @Test(arguments: [
        (HKCategoryValueAppetiteChanges.unspecified, "unspecified", "unspecified"),
        (HKCategoryValueAppetiteChanges.noChange, "noChange", "no change"),
        (HKCategoryValueAppetiteChanges.decreased, "decreased", "decreased"),
        (HKCategoryValueAppetiteChanges.increased, "increased", "increased")
    ])
    func appetiteChanges(value: HKCategoryValueAppetiteChanges, expectedCode: String, expectedDisplay: String) throws {
        let system: FHIRPrimitive<FHIRURI> = "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-appetite-changes"
        let observation = try createObservationFrom(
            type: .appetiteChanges,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .appetiteChanges,
            display: "Appetite Changes"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: expectedCode.asFHIRStringPrimitive(),
                display: expectedDisplay.asFHIRStringPrimitive(),
                system: system
            )
        ])))
    }

    @Test
    func environmentalAudioExposureEvent() throws {
        let observation = try createObservationFrom(
            type: .environmentalAudioExposureEvent,
            value: HKCategoryValueEnvironmentalAudioExposureEvent.momentaryLimit.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .environmentalAudioExposureEvent,
            display: "Environmental Audio Exposure Event"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "momentaryLimit".asFHIRStringPrimitive(),
                display: "momentary limit".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-environmental-audio-exposure-event".asFHIRURIPrimitive()
            )
        ])))
    }

    @Test
    func headphoneAudioExposureEvent() throws {
        let observation = try createObservationFrom(
            type: .headphoneAudioExposureEvent,
            value: HKCategoryValueHeadphoneAudioExposureEvent.sevenDayLimit.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .headphoneAudioExposureEvent,
            display: "Headphone Audio Exposure Event"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "sevenDayLimit".asFHIRStringPrimitive(),
                display: "seven day limit".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-headphone-audio-exposure-event".asFHIRURIPrimitive()
            )
        ])))
    }

    @Test
    func lowCardioFitnessEvent() throws {
        let observation = try createObservationFrom(
            type: .lowCardioFitnessEvent,
            value: HKCategoryValueLowCardioFitnessEvent.lowFitness.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .lowCardioFitnessEvent,
            display: "Low Cardio Fitness Event"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "lowFitness".asFHIRStringPrimitive(),
                display: "low fitness".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-low-cardio-fitness-event".asFHIRURIPrimitive()
            )
        ])))
    }
    
    @Test
    func lowCardioFitnessEventWithMetadata() throws {
        let observation = try createObservationFrom(
            type: .lowCardioFitnessEvent,
            value: HKCategoryValueLowCardioFitnessEvent.lowFitness.rawValue,
            metadata: [
                HKMetadataKeyLowCardioFitnessEventThreshold: HKQuantity(unit: HKUnit(from: "ml/(kg*min)"), doubleValue: 41)
            ]
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .lowCardioFitnessEvent,
            display: "Low Cardio Fitness Event"
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "lowFitness".asFHIRStringPrimitive(),
                display: "low fitness".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-low-cardio-fitness-event".asFHIRURIPrimitive()
            )
        ])))
        #expect(observation.component?.count == 1)
        let component = try #require(observation.component?.first)
        // The threshold is coded by its metadata key, never by the VO2max code it triggers on.
        #expect(component.code.coding == [
            Coding(
                code: "HKLowCardioFitnessEventThreshold".asFHIRStringPrimitive(),
                display: "Low Cardio Fitness Event Threshold".asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ])
        #expect(component.value == .quantity(Quantity(
            code: "mL/min/kg{body_wt}",
            system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
            unit: "mL/kg/min",
            value: 41.asFHIRDecimalPrimitive()
        )))
    }

    @Test
    func appleWalkingSteadinessEvent() throws {
        let values: [HKCategoryValueAppleWalkingSteadinessEvent] = [.initialLow, .initialVeryLow, .repeatLow, .repeatVeryLow]
        for value in values {
            let observation = try createObservationFrom(
                type: .appleWalkingSteadinessEvent,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .appleWalkingSteadinessEvent,
                display: "Apple Walking Steadiness Event"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: type(of: value).system
                )
            ])))
        }
    }

    @Test
    func appleWalkingSteadinessClassification() {
        let okClassification = HKAppleWalkingSteadinessClassification(
            rawValue: HKAppleWalkingSteadinessClassification.ok.rawValue
        )?.display
        #expect(okClassification == "ok")

        let lowClassification = HKAppleWalkingSteadinessClassification(
            rawValue: HKAppleWalkingSteadinessClassification.low.rawValue
        )?.display
        #expect(lowClassification == "low")

        let veryLowClassification = HKAppleWalkingSteadinessClassification(
            rawValue: HKAppleWalkingSteadinessClassification.veryLow.rawValue
        )?.display
        #expect(veryLowClassification == "very low")
    }
    
    @Test(arguments: [
        (HKCategoryTypeIdentifier.lowHeartRateEvent, "Low Heart Rate Event"),
        (HKCategoryTypeIdentifier.highHeartRateEvent, "High Heart Rate Event")
    ])
    func lowHeartRateEvent(category: HKCategoryTypeIdentifier, displayTitle: String) throws {
        let observation = try createObservationFrom(
            type: category,
            value: HKCategoryValue.notApplicable.rawValue,
            metadata: [
                HKMetadataKeyHeartRateEventThreshold: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 47)
            ]
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: category,
            display: displayTitle
        ))
        #expect(observation.value == nil)
        #expect(observation.component?.count == 1)
        let component = try #require(observation.component?.first)
        // The threshold is coded by its metadata key, never by the heart rate code it triggers on.
        #expect(component.code.coding == [
            Coding(
                code: "HKHeartRateEventThreshold".asFHIRStringPrimitive(),
                display: "Heart Rate Event Threshold".asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ])
        #expect(component.value == .quantity(Quantity(
            code: "/min",
            system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
            unit: "beats/minute",
            value: 47.asFHIRDecimalPrimitive()
        )))
    }

    @Test
    func pregnancyTestResult() throws {
        let values: [HKCategoryValuePregnancyTestResult] = [.negative, .positive, .indeterminate]
        for value in values {
            let observation = try createObservationFrom(
                type: .pregnancyTestResult,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .pregnancyTestResult,
                display: "Pregnancy Test Result"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: type(of: value).system
                )
            ])))
        }
    }
    
    @Test
    func pregnancy() throws {
        let observation = try createObservationFrom(
            type: .pregnancy,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .pregnancy,
            display: "Pregnancy"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func progesteroneTestResult() throws {
        let values: [HKCategoryValueProgesteroneTestResult] = [.indeterminate, .positive, .negative]
        for value in values {
            let observation = try createObservationFrom(
                type: .progesteroneTestResult,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .progesteroneTestResult,
                display: "Progesterone Test Result"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: type(of: value).system
                )
            ])))
        }
    }
    
    @Test
    func sexualActivityNoMetadata() throws {
        let observation = try createObservationFrom(
            type: .sexualActivity,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .sexualActivity,
            display: "Sexual Activity"
        ))
        #expect(observation.value == nil)
        #expect(observation.component == nil)
    }
    
    @Test
    func sexualActivityWithMetadata1() throws {
        let observation = try createObservationFrom(
            type: .sexualActivity,
            value: HKCategoryValue.notApplicable.rawValue,
            metadata: [
                HKMetadataKeySexualActivityProtectionUsed: true
            ]
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .sexualActivity,
            display: "Sexual Activity"
        ))
        #expect(observation.value == nil)
        #expect(observation.component?.count == 1)
        #expect(observation.component?.first?.value == .boolean(true))
    }
    
    @Test
    func sexualActivityWithMetadata2() throws {
        let observation = try createObservationFrom(
            type: .sexualActivity,
            value: HKCategoryValue.notApplicable.rawValue,
            metadata: [
                HKMetadataKeySexualActivityProtectionUsed: false
            ]
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .sexualActivity,
            display: "Sexual Activity"
        ))
        #expect(observation.value == nil)
        #expect(observation.component?.count == 1)
        #expect(observation.component?.first?.value == .boolean(false))
    }

    @Test
    func appleStandHour() throws {
        struct TestCase {
            let input: HKCategoryValueAppleStandHour
            let expectedOutput: Coding
        }
        let tests: [TestCase] = [
            .init(input: .stood, expectedOutput: Coding(
                code: "stood".asFHIRStringPrimitive(),
                display: "stood",
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-apple-stand-hour"
            )),
            .init(input: .idle, expectedOutput: Coding(
                code: "idle".asFHIRStringPrimitive(),
                display: "idle",
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-category-value-apple-stand-hour"
            ))
        ]
        for test in tests {
            let observation = try createObservationFrom(
                type: .appleStandHour,
                value: test.input.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .appleStandHour,
                display: "Apple Stand Hour"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [test.expectedOutput])))
        }
    }

    @Test
    func intermenstrualBleeding() throws {
        let observation = try createObservationFrom(
            type: .intermenstrualBleeding,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .intermenstrualBleeding,
            display: "Intermenstrual Bleeding"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func infrequentMenstrualCycles() throws {
        let observation = try createObservationFrom(
            type: .infrequentMenstrualCycles,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .infrequentMenstrualCycles,
            display: "Infrequent Menstrual Cycles"
        ))
        #expect(observation.value == nil)
    }
    
    @Test
    func irregularHeartRhythmEvent() throws {
        let observation = try createObservationFrom(
            type: .irregularHeartRhythmEvent,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .irregularHeartRhythmEvent,
            display: "Irregular Heart Rhythm Event"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func irregularMenstrualCycles() throws {
        let observation = try createObservationFrom(
            type: .irregularMenstrualCycles,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .irregularMenstrualCycles,
            display: "Irregular Menstrual Cycles"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func persistentIntermenstrualBleeding() throws {
        let observation = try createObservationFrom(
            type: .persistentIntermenstrualBleeding,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .persistentIntermenstrualBleeding,
            display: "Persistent Intermenstrual Bleeding"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func prolongedMenstrualPeriods() throws {
        let observation = try createObservationFrom(
            type: .prolongedMenstrualPeriods,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .prolongedMenstrualPeriods,
            display: "Prolonged Menstrual Periods"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func lactation() throws {
        let observation = try createObservationFrom(
            type: .lactation,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .lactation,
            display: "Lactation"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func handwashingEvent() throws {
        let observation = try createObservationFrom(
            type: .handwashingEvent,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .handwashingEvent,
            display: "Handwashing Event"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func toothbrushingEvent() throws {
        let observation = try createObservationFrom(
            type: .toothbrushingEvent,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .toothbrushingEvent,
            display: "Toothbrushing Event"
        ))
        #expect(observation.value == nil)
    }

    @Test
    func mindfulSession() throws {
        let observation = try createObservationFrom(
            type: .mindfulSession,
            value: HKCategoryValue.notApplicable.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: .mindfulSession,
            display: "Mindful Session"
        ))
        #expect(observation.value == nil)
    }

    
    // MARK: Symptom Tests


    func testSymptoms(type: HKCategoryTypeIdentifier, display: String) throws {
        let values: [HKCategoryValueSeverity] = [.moderate, .unspecified, .notPresent, .severe, .mild]
        for value in values {
            let observation = try createObservationFrom(
                type: type,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: type,
                display: display
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: Swift.type(of: value).system
                )
            ])))
        }
    }

    @Test
    func abdominalCramps() throws {
        try testSymptoms(type: .abdominalCramps, display: "Abdominal Cramps")
    }

    @Test
    func acne() throws {
        try testSymptoms(type: .acne, display: "Acne")
    }

    @Test
    func bladderIncontinence() throws {
        try testSymptoms(type: .bladderIncontinence, display: "Bladder Incontinence")
    }

    @Test
    func bloating() throws {
        try testSymptoms(type: .bloating, display: "Bloating")
    }

    @Test
    func breastPain() throws {
        try testSymptoms(type: .breastPain, display: "Breast Pain")
    }

    @Test
    func chestTightnessOrPain() throws {
        try testSymptoms(type: .chestTightnessOrPain, display: "Chest Tightness/Pain")
    }

    @Test
    func chills() throws {
        try testSymptoms(type: .chills, display: "Chills")
    }

    @Test
    func constipation() throws {
        try testSymptoms(type: .constipation, display: "Constipation")
    }

    @Test
    func coughing() throws {
        try testSymptoms(type: .coughing, display: "Coughing")
    }

    @Test
    func dizziness() throws {
        try testSymptoms(type: .dizziness, display: "Dizziness")
    }

    @Test
    func drySkin() throws {
        try testSymptoms(type: .drySkin, display: "Dry Skin")
    }

    @Test
    func fainting() throws {
        try testSymptoms(type: .fainting, display: "Fainting")
    }

    @Test
    func fever() throws {
        try testSymptoms(type: .fever, display: "Fever")
    }

    @Test
    func generalizedBodyAche() throws {
        try testSymptoms(type: .generalizedBodyAche, display: "Generalized Body Ache")
    }

    @Test
    func hairLoss() throws {
        try testSymptoms(type: .hairLoss, display: "Hair Loss")
    }

    @Test
    func headache() throws {
        try testSymptoms(type: .headache, display: "Headache")
    }

    @Test
    func heartburn() throws {
        try testSymptoms(type: .heartburn, display: "Heartburn")
    }

    @Test
    func hotFlashes() throws {
        try testSymptoms(type: .hotFlashes, display: "Hot Flashes")
    }

    @Test
    func lossOfSmell() throws {
        try testSymptoms(type: .lossOfSmell, display: "Loss of Smell")
    }

    @Test
    func lossOfTaste() throws {
        try testSymptoms(type: .lossOfTaste, display: "Loss of Taste")
    }

    @Test
    func lowerBackPain() throws {
        try testSymptoms(type: .lowerBackPain, display: "Lower Back Pain")
    }

    @Test
    func memoryLapse() throws {
        try testSymptoms(type: .memoryLapse, display: "Memory Lapse")
    }

    @Test
    func moodChanges() throws {
        let values: [HKCategoryValuePresence] = [.notPresent, .present]
        for value in values {
            let observation = try createObservationFrom(
                type: .moodChanges,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .moodChanges,
                display: "Mood Changes"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: type(of: value).system
                )
            ])))
        }
    }

    @Test
    func sleepChanges() throws {
        let values: [HKCategoryValuePresence] = [.notPresent, .present]
        for value in values {
            let observation = try createObservationFrom(
                type: .sleepChanges,
                value: value.rawValue
            )
            #expect(observation.code.coding?.last == createCategoryCoding(
                categoryType: .sleepChanges,
                display: "Sleep Changes"
            ))
            #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: value.code.asFHIRStringPrimitive(),
                    display: try #require(value.display).asFHIRStringPrimitive(),
                    system: type(of: value).system
                )
            ])))
        }
    }
    
    @Test(arguments: product([
        (HKCategoryTypeIdentifier.bleedingDuringPregnancy, "Bleeding During Pregnancy"),
        (HKCategoryTypeIdentifier.bleedingAfterPregnancy, "Bleeding After Pregnancy")
    ], [
        HKCategoryValueVaginalBleeding.none, .light, .medium, .heavy
    ]))
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *)
    func pregnancyBleeding(categoryInput: (HKCategoryTypeIdentifier, String), value: HKCategoryValueVaginalBleeding) throws {
        let (category, displayTitle) = categoryInput
        let observation = try createObservationFrom(
            type: category,
            value: value.rawValue
        )
        #expect(observation.code.coding?.last == createCategoryCoding(
            categoryType: category,
            display: displayTitle
        ))
        #expect(observation.value == .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: value.code.asFHIRStringPrimitive(),
                display: try #require(value.display).asFHIRStringPrimitive(),
                system: type(of: value).system
            )
        ])))
    }

    @Test
    func nausea() throws {
        try testSymptoms(type: .nausea, display: "Nausea")
    }

    @Test
    func nightSweats() throws {
        try testSymptoms(type: .nightSweats, display: "Night Sweats")
    }

    @Test
    func pelvicPain() throws {
        try testSymptoms(type: .pelvicPain, display: "Pelvic Pain")
    }

    @Test
    func rapidPoundingOrFlutteringHeartbeat() throws {
        try testSymptoms(type: .rapidPoundingOrFlutteringHeartbeat, display: "Rapid/Pounding/Fluttering Heartbeat")
    }

    @Test
    func runnyNose() throws {
        try testSymptoms(type: .runnyNose, display: "Runny Nose")
    }

    @Test
    func shortnessOfBreath() throws {
        try testSymptoms(type: .shortnessOfBreath, display: "Shortness of Breath")
    }

    @Test
    func sinusCongestion() throws {
        try testSymptoms(type: .sinusCongestion, display: "Sinus Congestion")
    }

    @Test
    func skippedHeartbeat() throws {
        try testSymptoms(type: .skippedHeartbeat, display: "Skipped Heartbeat")
    }

    @Test
    func soreThroat() throws {
        try testSymptoms(type: .soreThroat, display: "Sore Throat")
    }

    @Test
    func vaginalDryness() throws {
        try testSymptoms(type: .vaginalDryness, display: "Vaginal Dryness")
    }

    @Test
    func vomiting() throws {
        try testSymptoms(type: .vomiting, display: "Vomiting")
    }

    @Test
    func wheezing() throws {
        try testSymptoms(type: .wheezing, display: "Wheezing")
    }
}


func product<C1: Collection & Sendable, C2: Collection & Sendable>(
    _ first: C1,
    _ second: C2
) -> some Collection<(C1.Element, C2.Element)> & Sendable where C1.Element: Sendable, C2.Element: Sendable {
    first.lazy.flatMap { element1 in
        second.lazy.map { element2 in
            (element1, element2)
        }
    }
}

#endif
