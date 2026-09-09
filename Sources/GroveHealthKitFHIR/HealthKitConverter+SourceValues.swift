//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private struct HealthKitSleepStage {
        let sharedCode: String
        let sharedDisplay: String
        let sourceCode: String
        let sourceDisplay: String
    }

    static func workoutSample(_ sample: HKSample) throws -> HKWorkout {
        guard let workout = sample as? HKWorkout else {
            throw HealthKitConversionError.invalidValue
        }
        return workout
    }

    static func stateOfMindSample(_ sample: HKSample) throws -> HKStateOfMind {
        guard let stateOfMind = sample as? HKStateOfMind else {
            throw HealthKitConversionError.invalidValue
        }
        return stateOfMind
    }

    static func sessionRateValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        let quantitySample = try quantitySample(sample)
        let hours = quantitySample.endDate.timeIntervalSince(quantitySample.startDate) / 3_600
        return try fhirQuantity(
            value: quantitySample.quantity.doubleValue(for: .count()) / hours,
            contract: quantityContract(contract)
        )
    }

    static func assessmentScoreValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        guard let assessment = sample as? HKScoredAssessment else {
            throw HealthKitConversionError.invalidValue
        }
        return try fhirQuantity(value: Double(assessment.score), contract: quantityContract(contract))
    }

    static func sleepStageValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let stage = try sleepStage(try categorySample(sample).value, sampleType: sample.sampleType.identifier)
        return CodeableConcept(coding: [
            Coding(
                code: stage.sharedCode.asFHIRStringPrimitive(),
                display: stage.sharedDisplay.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
            ),
            Coding(
                code: stage.sourceCode.asFHIRStringPrimitive(),
                display: stage.sourceDisplay.asFHIRStringPrimitive(),
                system: Canonicals.healthKitSleepAnalysis
            )
        ])
    }

    static func quantitySample(_ sample: HKSample) throws -> HKQuantitySample {
        guard let quantitySample = sample as? HKQuantitySample else {
            throw HealthKitConversionError.invalidValue
        }
        return quantitySample
    }

    static func categorySample(_ sample: HKSample) throws -> HKCategorySample {
        guard let categorySample = sample as? HKCategorySample else {
            throw HealthKitConversionError.invalidValue
        }
        return categorySample
    }

    static func quantityContract(
        _ contract: HealthKitFHIRObservationContract
    ) throws -> QuantityContract {
        guard let quantity = contract.quantity else {
            throw HealthKitConversionError.invalidValue
        }
        return quantity
    }

    static func resultCodeSystem(_ contract: HealthKitFHIRObservationContract) throws -> String {
        guard let resultCodeSystem = contract.resultCodeSystem else {
            throw HealthKitConversionError.missingNormativeCode(contract.id)
        }
        return resultCodeSystem
    }

    static func fhirQuantity(
        value: Double,
        contract: QuantityContract
    ) throws -> Quantity {
        let canonicalValue = try HealthKitMobileCanonicalization.scalarDecimalValue(value)
        guard contract.valueDomain?.contains(canonicalValue) != false else {
            throw HealthKitConversionError.invalidValue
        }
        return Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.system)),
            unit: contract.unit.asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(canonicalValue))
        )
    }

    static func bloodPressureComponents(
        _ correlation: HKCorrelation,
        contract: HealthKitFHIRObservationContract
    ) throws -> [ObservationComponent] {
        try contract.components.map { component in
            let healthKitIdentifier: HKQuantityTypeIdentifier = component.id == "systolic"
                ? .bloodPressureSystolic
                : .bloodPressureDiastolic
            guard let sample = correlation.objects
                .compactMap({ $0 as? HKQuantitySample })
                .first(where: { $0.quantityType.identifier == healthKitIdentifier.rawValue }) else {
                throw HealthKitConversionError.missingRequiredComponent(
                    sampleType: correlation.correlationType.identifier,
                    component: component.id
                )
            }
            guard let componentQuantity = component.quantity else {
                throw HealthKitConversionError.invalidValue
            }
            return ObservationComponent(
                code: CodeableConcept(coding: [
                    Coding(
                        code: component.code.asFHIRStringPrimitive(),
                        system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
                    )
                ]),
                value: .quantity(try fhirQuantity(
                    value: sample.quantity.doubleValue(for: .millimeterOfMercury()),
                    contract: componentQuantity
                ))
            )
        }
    }

    private static func sleepStage(
        _ value: Int,
        sampleType: String
    ) throws -> HealthKitSleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            HealthKitSleepStage(
                sharedCode: "in-bed",
                sharedDisplay: "In bed",
                sourceCode: "inBed",
                sourceDisplay: "In bed"
            )
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            HealthKitSleepStage(
                sharedCode: "asleep-unspecified",
                sharedDisplay: "Asleep, unspecified stage",
                sourceCode: "asleepUnspecified",
                sourceDisplay: "Asleep, unspecified"
            )
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            HealthKitSleepStage(
                sharedCode: "awake",
                sharedDisplay: "Awake",
                sourceCode: "awake",
                sourceDisplay: "Awake"
            )
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            HealthKitSleepStage(
                sharedCode: "light",
                sharedDisplay: "Light sleep",
                sourceCode: "asleepCore",
                sourceDisplay: "Asleep, core"
            )
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            HealthKitSleepStage(
                sharedCode: "deep",
                sharedDisplay: "Deep sleep",
                sourceCode: "asleepDeep",
                sourceDisplay: "Asleep, deep"
            )
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            HealthKitSleepStage(
                sharedCode: "rem",
                sharedDisplay: "REM sleep",
                sourceCode: "asleepREM",
                sourceDisplay: "Asleep, REM"
            )
        default:
            throw HealthKitConversionError.unsupportedSampleValue(
                sampleType: sampleType,
                value: value
            )
        }
    }
}

#endif
