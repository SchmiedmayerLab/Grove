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
extension HealthKitFHIRCatalog {
    // A closed source-type dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func quantityBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKQuantityTypeIdentifier(rawValue: identifier) {
        case .activeEnergyBurned:
            return .quantity(GroveFHIRMeasurementCatalog.activeEnergy, unit: .kilocalorie())
        case .appleExerciseTime:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.appleExerciseTime, unit: .minute())
        case .appleMoveTime:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.appleMoveTime, unit: .minute())
        case .appleSleepingBreathingDisturbances:
            return .sessionRate(GroveFHIRHealthKitMeasurementCatalog.sleepingBreathingDisturbances)
        case .appleSleepingWristTemperature:
            return .quantity(GroveFHIRMeasurementCatalog.skinTemperature, unit: .degreeCelsius())
        case .appleStandTime:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.appleStandTime, unit: .minute())
        case .appleWalkingSteadiness:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.walkingSteadiness)
        case .atrialFibrillationBurden:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.atrialFibrillationBurden)
        case .basalBodyTemperature:
            return .quantity(GroveFHIRMeasurementCatalog.basalBodyTemperature, unit: .degreeCelsius())
        case .basalEnergyBurned:
            return .quantity(GroveFHIRMeasurementCatalog.basalEnergy, unit: .kilocalorie())
        case .bloodAlcoholContent:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.bloodAlcoholContent)
        case .bloodGlucose:
            return .quantity(
                GroveFHIRMeasurementCatalog.bloodGlucoseUnspecifiedSpecimen,
                unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            )
        case .bodyFatPercentage:
            return .percent(GroveFHIRMeasurementCatalog.bodyFatPercentage)
        case .bodyMass:
            return .quantity(GroveFHIRMeasurementCatalog.bodyWeight, unit: .gramUnit(with: .kilo))
        case .bodyMassIndex:
            return .quantity(.bodyMassIndex, unit: .count())
        case .bodyTemperature:
            return .quantity(GroveFHIRMeasurementCatalog.bodyTemperature, unit: .degreeCelsius())
        case .crossCountrySkiingSpeed, .cyclingSpeed, .paddleSportsSpeed, .rowingSpeed, .runningSpeed:
            return .quantity(GroveFHIRMeasurementCatalog.speed, unit: .meter().unitDivided(by: .second()))
        case .cyclingCadence:
            return .quantity(GroveFHIRMeasurementCatalog.cyclingCadence, unit: .count().unitDivided(by: .minute()))
        case .cyclingFunctionalThresholdPower:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.cyclingFunctionalThresholdPower, unit: .watt())
        case .cyclingPower, .runningPower:
            return .quantity(GroveFHIRMeasurementCatalog.power, unit: .watt())
        case .dietaryBiotin:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryBiotin, unit: .gramUnit(with: .micro))
        case .dietaryCaffeine:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryCaffeine, unit: .gramUnit(with: .milli))
        case .dietaryCalcium:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryCalcium, unit: .gramUnit(with: .milli))
        case .dietaryCarbohydrates:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryCarbohydrates, unit: .gram())
        case .dietaryChloride:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryChloride, unit: .gramUnit(with: .milli))
        case .dietaryCholesterol:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryCholesterol, unit: .gramUnit(with: .milli))
        case .dietaryChromium:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryChromium, unit: .gramUnit(with: .micro))
        case .dietaryCopper:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryCopper, unit: .gramUnit(with: .micro))
        case .dietaryEnergyConsumed:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryEnergy, unit: .kilocalorie())
        case .dietaryFatMonounsaturated:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFatMonounsaturated, unit: .gram())
        case .dietaryFatPolyunsaturated:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFatPolyunsaturated, unit: .gram())
        case .dietaryFatSaturated:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFatSaturated, unit: .gram())
        case .dietaryFatTotal:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFatTotal, unit: .gram())
        case .dietaryFiber:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFiber, unit: .gram())
        case .dietaryFolate:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryFolate, unit: .gramUnit(with: .micro))
        case .dietaryIodine:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryIodine, unit: .gramUnit(with: .micro))
        case .dietaryIron:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryIron, unit: .gramUnit(with: .milli))
        case .dietaryMagnesium:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryMagnesium, unit: .gramUnit(with: .milli))
        case .dietaryManganese:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryManganese, unit: .gramUnit(with: .milli))
        case .dietaryMolybdenum:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryMolybdenum, unit: .gramUnit(with: .micro))
        case .dietaryNiacin:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryNiacin, unit: .gramUnit(with: .milli))
        case .dietaryPantothenicAcid:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryPantothenicAcid, unit: .gramUnit(with: .milli))
        case .dietaryPhosphorus:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryPhosphorus, unit: .gramUnit(with: .milli))
        case .dietaryPotassium:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryPotassium, unit: .gramUnit(with: .milli))
        case .dietaryProtein:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryProtein, unit: .gram())
        case .dietaryRiboflavin:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryRiboflavin, unit: .gramUnit(with: .milli))
        case .dietarySelenium:
            return .quantity(GroveFHIRMeasurementCatalog.dietarySelenium, unit: .gramUnit(with: .micro))
        case .dietarySodium:
            return .quantity(GroveFHIRMeasurementCatalog.dietarySodium, unit: .gramUnit(with: .milli))
        case .dietarySugar:
            return .quantity(GroveFHIRMeasurementCatalog.dietarySugar, unit: .gram())
        case .dietaryThiamin:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryThiamin, unit: .gramUnit(with: .milli))
        case .dietaryVitaminA:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminA, unit: .gramUnit(with: .micro))
        case .dietaryVitaminB12:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminB12, unit: .gramUnit(with: .micro))
        case .dietaryVitaminB6:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminB6, unit: .gramUnit(with: .milli))
        case .dietaryVitaminC:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminC, unit: .gramUnit(with: .milli))
        case .dietaryVitaminD:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminD, unit: .gramUnit(with: .micro))
        case .dietaryVitaminE:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminE, unit: .gramUnit(with: .milli))
        case .dietaryVitaminK:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryVitaminK, unit: .gramUnit(with: .micro))
        case .dietaryWater:
            return .quantity(GroveFHIRMeasurementCatalog.fluidIntake, unit: .literUnit(with: .milli))
        case .dietaryZinc:
            return .quantity(GroveFHIRMeasurementCatalog.dietaryZinc, unit: .gramUnit(with: .milli))
        case .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .distanceWheelchair,
             .distanceDownhillSnowSports,
             .distanceCrossCountrySkiing,
             .distancePaddleSports,
             .distanceRowing,
             .distanceSkatingSports:
            return .quantity(GroveFHIRMeasurementCatalog.distance, unit: .meter())
        case .electrodermalActivity:
            return .quantity(GroveFHIRMeasurementCatalog.electrodermalActivity, unit: .siemenUnit(with: .micro))
        case .environmentalAudioExposure:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.environmentalAudioExposure,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .environmentalSoundReduction:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.environmentalSoundReduction,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .estimatedWorkoutEffortScore, .workoutEffortScore:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.workoutEffortScore, unit: .appleEffortScore())
        case .flightsClimbed:
            return .quantity(GroveFHIRMeasurementCatalog.flightsClimbed, unit: .count())
        case .forcedExpiratoryVolume1:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.forcedExpiratoryVolume1, unit: .liter())
        case .forcedVitalCapacity:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.forcedVitalCapacity, unit: .liter())
        case .headphoneAudioExposure:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.headphoneAudioExposure,
                unit: .decibelAWeightedSoundPressureLevel()
            )
        case .heartRate:
            return .quantity(GroveFHIRMeasurementCatalog.heartRate, unit: .count().unitDivided(by: .minute()))
        case .heartRateRecoveryOneMinute:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.heartRateRecoveryOneMinute,
                unit: .count().unitDivided(by: .minute())
            )
        case .heartRateVariabilitySDNN:
            return .quantity(GroveFHIRMeasurementCatalog.heartRateVariabilitySdnn, unit: .secondUnit(with: .milli))
        case .height:
            return .quantity(GroveFHIRMeasurementCatalog.bodyHeight, unit: .meterUnit(with: .centi))
        case .inhalerUsage:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.inhalerUsage, unit: .count())
        case .insulinDelivery:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.insulinDelivery, unit: .internationalUnit())
        case .leanBodyMass:
            return .quantity(GroveFHIRMeasurementCatalog.leanBodyMass, unit: .gramUnit(with: .kilo))
        case .numberOfAlcoholicBeverages:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.numberOfAlcoholicBeverages, unit: .count())
        case .numberOfTimesFallen:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.numberOfTimesFallen, unit: .count())
        case .oxygenSaturation:
            return .percent(GroveFHIRMeasurementCatalog.oxygenSaturation)
        case .peakExpiratoryFlowRate:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.peakExpiratoryFlowRate,
                unit: .liter().unitDivided(by: .minute())
            )
        case .peripheralPerfusionIndex:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.peripheralPerfusionIndex)
        case .physicalEffort:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.physicalEffort,
                unit: .kilocalorie().unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .hour())
            )
        case .pushCount:
            return .quantity(GroveFHIRMeasurementCatalog.wheelchairPushCount, unit: .count())
        case .respiratoryRate:
            return .quantity(GroveFHIRMeasurementCatalog.respiratoryRate, unit: .count().unitDivided(by: .minute()))
        case .restingHeartRate:
            return .quantity(GroveFHIRMeasurementCatalog.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        case .runningGroundContactTime:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.runningGroundContactTime, unit: .secondUnit(with: .milli))
        case .runningStrideLength:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.runningStrideLength, unit: .meter())
        case .runningVerticalOscillation:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.runningVerticalOscillation, unit: .meterUnit(with: .centi))
        case .sixMinuteWalkTestDistance:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.sixMinuteWalkTestDistance, unit: .meter())
        case .stairAscentSpeed:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.stairAscentSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .stairDescentSpeed:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.stairDescentSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .stepCount:
            return .quantity(GroveFHIRMeasurementCatalog.stepCount, unit: .count())
        case .swimmingStrokeCount:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.swimmingStrokeCount, unit: .count())
        case .timeInDaylight:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.timeInDaylight, unit: .minute())
        case .underwaterDepth:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.underwaterDepth, unit: .meter())
        case .uvExposure:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.uvExposure, unit: .count())
        case .vo2Max:
            return .quantity(
                GroveFHIRMeasurementCatalog.vo2Max,
                unit: .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
            )
        case .waistCircumference:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.waistCircumference, unit: .meterUnit(with: .centi))
        case .walkingAsymmetryPercentage:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.walkingAsymmetry)
        case .walkingDoubleSupportPercentage:
            return .percent(GroveFHIRHealthKitMeasurementCatalog.walkingDoubleSupport)
        case .walkingHeartRateAverage:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.walkingHeartRateAverage,
                unit: .count().unitDivided(by: .minute())
            )
        case .walkingSpeed:
            return .quantity(
                GroveFHIRHealthKitMeasurementCatalog.walkingSpeed,
                unit: .meter().unitDivided(by: .second())
            )
        case .walkingStepLength:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.walkingStepLength, unit: .meterUnit(with: .centi))
        case .waterTemperature:
            return .quantity(GroveFHIRHealthKitMeasurementCatalog.waterTemperature, unit: .degreeCelsius())
        default:
            return nil
        }
    }
}

#endif
