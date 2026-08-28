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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitCatalog {
    // A closed source-type dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func quantityBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKQuantityTypeIdentifier(rawValue: identifier) {
        case .activeEnergyBurned:
            return .quantity(MeasurementCatalog.activeEnergy, unit: .kilocalorie())
        case .appleExerciseTime:
            return .quantity(HealthKitMeasurementCatalog.appleExerciseTime, unit: .minute())
        case .appleMoveTime:
            return .quantity(HealthKitMeasurementCatalog.appleMoveTime, unit: .minute())
        case .appleSleepingBreathingDisturbances:
            return .sessionRate(HealthKitMeasurementCatalog.sleepingBreathingDisturbances)
        case .appleSleepingWristTemperature:
            return .quantity(MeasurementCatalog.skinTemperature, unit: .degreeCelsius())
        case .appleStandTime:
            return .quantity(HealthKitMeasurementCatalog.appleStandTime, unit: .minute())
        case .appleWalkingSteadiness:
            return .percent(HealthKitMeasurementCatalog.walkingSteadiness)
        case .atrialFibrillationBurden:
            return .percent(HealthKitMeasurementCatalog.atrialFibrillationBurden)
        case .basalBodyTemperature:
            return .quantity(MeasurementCatalog.basalBodyTemperature, unit: .degreeCelsius())
        case .basalEnergyBurned:
            return .quantity(MeasurementCatalog.basalEnergy, unit: .kilocalorie())
        case .bloodAlcoholContent:
            return .percent(HealthKitMeasurementCatalog.bloodAlcoholContent)
        case .bloodGlucose:
            return .quantity(
                MeasurementCatalog.bloodGlucoseUnspecifiedSpecimen,
                unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            )
        case .bodyFatPercentage:
            return .percent(MeasurementCatalog.bodyFatPercentage)
        case .bodyMass:
            return .quantity(MeasurementCatalog.bodyWeight, unit: .gramUnit(with: .kilo))
        case .bodyMassIndex:
            return .quantity(.bodyMassIndex, unit: .count())
        case .bodyTemperature:
            return .quantity(MeasurementCatalog.bodyTemperature, unit: .degreeCelsius())
        case .crossCountrySkiingSpeed, .cyclingSpeed, .paddleSportsSpeed, .rowingSpeed, .runningSpeed:
            return .quantity(MeasurementCatalog.speed, unit: .meter().unitDivided(by: .second()))
        case .cyclingCadence:
            return .quantity(MeasurementCatalog.cyclingCadence, unit: .count().unitDivided(by: .minute()))
        case .cyclingFunctionalThresholdPower:
            return .quantity(HealthKitMeasurementCatalog.cyclingFunctionalThresholdPower, unit: .watt())
        case .cyclingPower, .runningPower:
            return .quantity(MeasurementCatalog.power, unit: .watt())
        case .dietaryBiotin:
            return .quantity(MeasurementCatalog.dietaryBiotin, unit: .gramUnit(with: .micro))
        case .dietaryCaffeine:
            return .quantity(MeasurementCatalog.dietaryCaffeine, unit: .gramUnit(with: .milli))
        case .dietaryCalcium:
            return .quantity(MeasurementCatalog.dietaryCalcium, unit: .gramUnit(with: .milli))
        case .dietaryCarbohydrates:
            return .quantity(MeasurementCatalog.dietaryCarbohydrates, unit: .gram())
        case .dietaryChloride:
            return .quantity(MeasurementCatalog.dietaryChloride, unit: .gramUnit(with: .milli))
        case .dietaryCholesterol:
            return .quantity(MeasurementCatalog.dietaryCholesterol, unit: .gramUnit(with: .milli))
        case .dietaryChromium:
            return .quantity(MeasurementCatalog.dietaryChromium, unit: .gramUnit(with: .micro))
        case .dietaryCopper:
            return .quantity(MeasurementCatalog.dietaryCopper, unit: .gramUnit(with: .micro))
        case .dietaryEnergyConsumed:
            return .quantity(MeasurementCatalog.dietaryEnergy, unit: .kilocalorie())
        case .dietaryFatMonounsaturated:
            return .quantity(MeasurementCatalog.dietaryFatMonounsaturated, unit: .gram())
        case .dietaryFatPolyunsaturated:
            return .quantity(MeasurementCatalog.dietaryFatPolyunsaturated, unit: .gram())
        case .dietaryFatSaturated:
            return .quantity(MeasurementCatalog.dietaryFatSaturated, unit: .gram())
        case .dietaryFatTotal:
            return .quantity(MeasurementCatalog.dietaryFatTotal, unit: .gram())
        case .dietaryFiber:
            return .quantity(MeasurementCatalog.dietaryFiber, unit: .gram())
        case .dietaryFolate:
            return .quantity(MeasurementCatalog.dietaryFolate, unit: .gramUnit(with: .micro))
        case .dietaryIodine:
            return .quantity(MeasurementCatalog.dietaryIodine, unit: .gramUnit(with: .micro))
        case .dietaryIron:
            return .quantity(MeasurementCatalog.dietaryIron, unit: .gramUnit(with: .milli))
        case .dietaryMagnesium:
            return .quantity(MeasurementCatalog.dietaryMagnesium, unit: .gramUnit(with: .milli))
        case .dietaryManganese:
            return .quantity(MeasurementCatalog.dietaryManganese, unit: .gramUnit(with: .milli))
        case .dietaryMolybdenum:
            return .quantity(MeasurementCatalog.dietaryMolybdenum, unit: .gramUnit(with: .micro))
        case .dietaryNiacin:
            return .quantity(MeasurementCatalog.dietaryNiacin, unit: .gramUnit(with: .milli))
        case .dietaryPantothenicAcid:
            return .quantity(MeasurementCatalog.dietaryPantothenicAcid, unit: .gramUnit(with: .milli))
        case .dietaryPhosphorus:
            return .quantity(MeasurementCatalog.dietaryPhosphorus, unit: .gramUnit(with: .milli))
        case .dietaryPotassium:
            return .quantity(MeasurementCatalog.dietaryPotassium, unit: .gramUnit(with: .milli))
        case .dietaryProtein:
            return .quantity(MeasurementCatalog.dietaryProtein, unit: .gram())
        case .dietaryRiboflavin:
            return .quantity(MeasurementCatalog.dietaryRiboflavin, unit: .gramUnit(with: .milli))
        case .dietarySelenium:
            return .quantity(MeasurementCatalog.dietarySelenium, unit: .gramUnit(with: .micro))
        case .dietarySodium:
            return .quantity(MeasurementCatalog.dietarySodium, unit: .gramUnit(with: .milli))
        case .dietarySugar:
            return .quantity(MeasurementCatalog.dietarySugar, unit: .gram())
        case .dietaryThiamin:
            return .quantity(MeasurementCatalog.dietaryThiamin, unit: .gramUnit(with: .milli))
        case .dietaryVitaminA:
            return .quantity(MeasurementCatalog.dietaryVitaminA, unit: .gramUnit(with: .micro))
        case .dietaryVitaminB12:
            return .quantity(MeasurementCatalog.dietaryVitaminB12, unit: .gramUnit(with: .micro))
        case .dietaryVitaminB6:
            return .quantity(MeasurementCatalog.dietaryVitaminB6, unit: .gramUnit(with: .milli))
        case .dietaryVitaminC:
            return .quantity(MeasurementCatalog.dietaryVitaminC, unit: .gramUnit(with: .milli))
        case .dietaryVitaminD:
            return .quantity(MeasurementCatalog.dietaryVitaminD, unit: .gramUnit(with: .micro))
        case .dietaryVitaminE:
            return .quantity(MeasurementCatalog.dietaryVitaminE, unit: .gramUnit(with: .milli))
        case .dietaryVitaminK:
            return .quantity(MeasurementCatalog.dietaryVitaminK, unit: .gramUnit(with: .micro))
        case .dietaryWater:
            return .quantity(MeasurementCatalog.fluidIntake, unit: .literUnit(with: .milli))
        case .dietaryZinc:
            return .quantity(MeasurementCatalog.dietaryZinc, unit: .gramUnit(with: .milli))
        case .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .distanceWheelchair,
             .distanceDownhillSnowSports,
             .distanceCrossCountrySkiing,
             .distancePaddleSports,
             .distanceRowing,
             .distanceSkatingSports:
            return .quantity(MeasurementCatalog.distance, unit: .meter())
        case .electrodermalActivity:
            return .quantity(MeasurementCatalog.electrodermalActivity, unit: .siemenUnit(with: .micro))
        case .environmentalAudioExposure:
            return .quantity(
                HealthKitMeasurementCatalog.environmentalAudioExposure,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .environmentalSoundReduction:
            return .quantity(
                HealthKitMeasurementCatalog.environmentalSoundReduction,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .estimatedWorkoutEffortScore, .workoutEffortScore:
            return .quantity(HealthKitMeasurementCatalog.workoutEffortScore, unit: .appleEffortScore())
        case .flightsClimbed:
            return .quantity(MeasurementCatalog.flightsClimbed, unit: .count())
        case .forcedExpiratoryVolume1:
            return .quantity(HealthKitMeasurementCatalog.forcedExpiratoryVolume1, unit: .liter())
        case .forcedVitalCapacity:
            return .quantity(HealthKitMeasurementCatalog.forcedVitalCapacity, unit: .liter())
        case .headphoneAudioExposure:
            return .quantity(
                HealthKitMeasurementCatalog.headphoneAudioExposure,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .heartRate:
            return .quantity(MeasurementCatalog.heartRate, unit: .count().unitDivided(by: .minute()))
        case .heartRateRecoveryOneMinute:
            return .quantity(
                HealthKitMeasurementCatalog.heartRateRecoveryOneMinute,
                unit: .count().unitDivided(by: .minute())
            )
        case .heartRateVariabilitySDNN:
            return .quantity(MeasurementCatalog.heartRateVariabilitySdnn, unit: .secondUnit(with: .milli))
        case .height:
            return .quantity(MeasurementCatalog.bodyHeight, unit: .meterUnit(with: .centi))
        case .inhalerUsage:
            return .quantity(HealthKitMeasurementCatalog.inhalerUsage, unit: .count())
        case .insulinDelivery:
            return .quantity(HealthKitMeasurementCatalog.insulinDelivery, unit: .internationalUnit())
        case .leanBodyMass:
            return .quantity(MeasurementCatalog.leanBodyMass, unit: .gramUnit(with: .kilo))
        case .numberOfAlcoholicBeverages:
            return .quantity(HealthKitMeasurementCatalog.numberOfAlcoholicBeverages, unit: .count())
        case .numberOfTimesFallen:
            return .quantity(HealthKitMeasurementCatalog.numberOfTimesFallen, unit: .count())
        case .oxygenSaturation:
            return .percent(MeasurementCatalog.oxygenSaturation)
        case .peakExpiratoryFlowRate:
            return .quantity(
                HealthKitMeasurementCatalog.peakExpiratoryFlowRate,
                unit: .liter().unitDivided(by: .minute())
            )
        case .peripheralPerfusionIndex:
            return .percent(HealthKitMeasurementCatalog.peripheralPerfusionIndex)
        case .physicalEffort:
            return .quantity(
                HealthKitMeasurementCatalog.physicalEffort,
                unit: .kilocalorie().unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .hour())
            )
        case .pushCount:
            return .quantity(MeasurementCatalog.wheelchairPushCount, unit: .count())
        case .respiratoryRate:
            return .quantity(MeasurementCatalog.respiratoryRate, unit: .count().unitDivided(by: .minute()))
        case .restingHeartRate:
            return .quantity(MeasurementCatalog.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        case .runningGroundContactTime:
            return .quantity(HealthKitMeasurementCatalog.runningGroundContactTime, unit: .secondUnit(with: .milli))
        case .runningStrideLength:
            return .quantity(HealthKitMeasurementCatalog.runningStrideLength, unit: .meter())
        case .runningVerticalOscillation:
            return .quantity(HealthKitMeasurementCatalog.runningVerticalOscillation, unit: .meterUnit(with: .centi))
        case .sixMinuteWalkTestDistance:
            return .quantity(HealthKitMeasurementCatalog.sixMinuteWalkTestDistance, unit: .meter())
        case .stairAscentSpeed:
            return .quantity(
                HealthKitMeasurementCatalog.stairAscentSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .stairDescentSpeed:
            return .quantity(
                HealthKitMeasurementCatalog.stairDescentSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .stepCount:
            return .quantity(MeasurementCatalog.stepCount, unit: .count())
        case .swimmingStrokeCount:
            return .quantity(HealthKitMeasurementCatalog.swimmingStrokeCount, unit: .count())
        case .timeInDaylight:
            return .quantity(HealthKitMeasurementCatalog.timeInDaylight, unit: .minute())
        case .underwaterDepth:
            return .quantity(HealthKitMeasurementCatalog.underwaterDepth, unit: .meter())
        case .uvExposure:
            return .quantity(HealthKitMeasurementCatalog.uvExposure, unit: .count())
        case .vo2Max:
            return .quantity(
                MeasurementCatalog.vo2Max,
                unit: .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
            )
        case .waistCircumference:
            return .quantity(HealthKitMeasurementCatalog.waistCircumference, unit: .meterUnit(with: .centi))
        case .walkingAsymmetryPercentage:
            return .percent(HealthKitMeasurementCatalog.walkingAsymmetry)
        case .walkingDoubleSupportPercentage:
            return .percent(HealthKitMeasurementCatalog.walkingDoubleSupport)
        case .walkingHeartRateAverage:
            return .quantity(
                HealthKitMeasurementCatalog.walkingHeartRateAverage,
                unit: .count().unitDivided(by: .minute())
            )
        case .walkingSpeed:
            return .quantity(
                HealthKitMeasurementCatalog.walkingSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .walkingStepLength:
            return .quantity(HealthKitMeasurementCatalog.walkingStepLength, unit: .meterUnit(with: .centi))
        case .waterTemperature:
            return .quantity(HealthKitMeasurementCatalog.waterTemperature, unit: .degreeCelsius())
        default:
            return nil
        }
    }
}

#endif
