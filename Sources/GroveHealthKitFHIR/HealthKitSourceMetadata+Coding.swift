//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitSourceMetadata {
    private static let codingTables: [String: [Int: Coding]] = [
        HKMetadataKeyAppleECGAlgorithmVersion: codings(HKAppleECGAlgorithmVersion.self, displays: [
            HKAppleECGAlgorithmVersion.version1.rawValue: "Version 1",
            HKAppleECGAlgorithmVersion.version2.rawValue: "Version 2"
        ]),
        HKMetadataKeyBloodGlucoseMealTime: codings(HKBloodGlucoseMealTime.self, displays: [
            HKBloodGlucoseMealTime.preprandial.rawValue: "Preprandial",
            HKBloodGlucoseMealTime.postprandial.rawValue: "Postprandial"
        ]),
        HKMetadataKeyBodyTemperatureSensorLocation: codings(HKBodyTemperatureSensorLocation.self, displays: [
            HKBodyTemperatureSensorLocation.other.rawValue: "Other",
            HKBodyTemperatureSensorLocation.armpit.rawValue: "Armpit",
            HKBodyTemperatureSensorLocation.body.rawValue: "Body",
            HKBodyTemperatureSensorLocation.ear.rawValue: "Ear",
            HKBodyTemperatureSensorLocation.finger.rawValue: "Finger",
            HKBodyTemperatureSensorLocation.gastroIntestinal.rawValue: "Gastro Intestinal",
            HKBodyTemperatureSensorLocation.mouth.rawValue: "Mouth",
            HKBodyTemperatureSensorLocation.rectum.rawValue: "Rectum",
            HKBodyTemperatureSensorLocation.toe.rawValue: "Toe",
            HKBodyTemperatureSensorLocation.earDrum.rawValue: "Ear Drum",
            HKBodyTemperatureSensorLocation.temporalArtery.rawValue: "Temporal Artery",
            HKBodyTemperatureSensorLocation.forehead.rawValue: "Forehead"
        ]),
        HKMetadataKeyCyclingFunctionalThresholdPowerTestType: codings(HKCyclingFunctionalThresholdPowerTestType.self, displays: [
            HKCyclingFunctionalThresholdPowerTestType.maxExercise60Minute.rawValue: "Max Exercise 60Minute",
            HKCyclingFunctionalThresholdPowerTestType.maxExercise20Minute.rawValue: "Max Exercise 20Minute",
            HKCyclingFunctionalThresholdPowerTestType.rampTest.rawValue: "Ramp Test",
            HKCyclingFunctionalThresholdPowerTestType.predictionExercise.rawValue: "Prediction Exercise"
        ]),
        HKMetadataKeyDevicePlacementSide: codings(HKDevicePlacementSide.self, displays: [
            HKDevicePlacementSide.unknown.rawValue: "Unknown",
            HKDevicePlacementSide.left.rawValue: "Left",
            HKDevicePlacementSide.right.rawValue: "Right",
            HKDevicePlacementSide.central.rawValue: "Central"
        ]),
        HKMetadataKeyHeartRateMotionContext: codings(HKHeartRateMotionContext.self, displays: [
            HKHeartRateMotionContext.notSet.rawValue: "Not Set",
            HKHeartRateMotionContext.sedentary.rawValue: "Sedentary",
            HKHeartRateMotionContext.active.rawValue: "Active"
        ]),
        HKMetadataKeyHeartRateRecoveryTestType: codings(HKHeartRateRecoveryTestType.self, displays: [
            HKHeartRateRecoveryTestType.maxExercise.rawValue: "Max Exercise",
            HKHeartRateRecoveryTestType.predictionSubMaxExercise.rawValue: "Prediction Sub Max Exercise",
            HKHeartRateRecoveryTestType.predictionNonExercise.rawValue: "Prediction Non Exercise"
        ]),
        HKMetadataKeyHeartRateSensorLocation: codings(HKHeartRateSensorLocation.self, displays: [
            HKHeartRateSensorLocation.other.rawValue: "Other",
            HKHeartRateSensorLocation.chest.rawValue: "Chest",
            HKHeartRateSensorLocation.wrist.rawValue: "Wrist",
            HKHeartRateSensorLocation.finger.rawValue: "Finger",
            HKHeartRateSensorLocation.hand.rawValue: "Hand",
            HKHeartRateSensorLocation.earLobe.rawValue: "Ear Lobe",
            HKHeartRateSensorLocation.foot.rawValue: "Foot"
        ]),
        HKMetadataKeyInsulinDeliveryReason: codings(HKInsulinDeliveryReason.self, displays: [
            HKInsulinDeliveryReason.basal.rawValue: "Basal",
            HKInsulinDeliveryReason.bolus.rawValue: "Bolus"
        ]),
        HKMetadataKeyPhysicalEffortEstimationType: codings(HKPhysicalEffortEstimationType.self, displays: [
            HKPhysicalEffortEstimationType.activityLookup.rawValue: "Activity Lookup",
            HKPhysicalEffortEstimationType.deviceSensed.rawValue: "Device Sensed"
        ]),
        HKMetadataKeySwimmingStrokeStyle: codings(HKSwimmingStrokeStyle.self, displays: [
            HKSwimmingStrokeStyle.unknown.rawValue: "Unknown",
            HKSwimmingStrokeStyle.mixed.rawValue: "Mixed",
            HKSwimmingStrokeStyle.freestyle.rawValue: "Freestyle",
            HKSwimmingStrokeStyle.backstroke.rawValue: "Backstroke",
            HKSwimmingStrokeStyle.breaststroke.rawValue: "Breaststroke",
            HKSwimmingStrokeStyle.butterfly.rawValue: "Butterfly",
            HKSwimmingStrokeStyle.kickboard.rawValue: "Kickboard"
        ]),
        HKMetadataKeyUserMotionContext: codings(HKUserMotionContext.self, displays: [
            HKUserMotionContext.notSet.rawValue: "Not Set",
            HKUserMotionContext.stationary.rawValue: "Stationary",
            HKUserMotionContext.active.rawValue: "Active"
        ]),
        HKMetadataKeyVO2MaxTestType: codings(HKVO2MaxTestType.self, displays: [
            HKVO2MaxTestType.maxExercise.rawValue: "Max Exercise",
            HKVO2MaxTestType.predictionSubMaxExercise.rawValue: "Prediction Sub Max Exercise",
            HKVO2MaxTestType.predictionNonExercise.rawValue: "Prediction Non Exercise"
        ]),
        HKMetadataKeyWaterSalinity: codings(HKWaterSalinity.self, displays: [
            HKWaterSalinity.freshWater.rawValue: "Fresh Water",
            HKWaterSalinity.saltWater.rawValue: "Salt Water"
        ]),
        HKMetadataKeyWeatherCondition: codings(HKWeatherCondition.self, displays: [
            HKWeatherCondition.none.rawValue: "None",
            HKWeatherCondition.clear.rawValue: "Clear",
            HKWeatherCondition.fair.rawValue: "Fair",
            HKWeatherCondition.partlyCloudy.rawValue: "Partly Cloudy",
            HKWeatherCondition.mostlyCloudy.rawValue: "Mostly Cloudy",
            HKWeatherCondition.cloudy.rawValue: "Cloudy",
            HKWeatherCondition.foggy.rawValue: "Foggy",
            HKWeatherCondition.haze.rawValue: "Haze",
            HKWeatherCondition.windy.rawValue: "Windy",
            HKWeatherCondition.blustery.rawValue: "Blustery",
            HKWeatherCondition.smoky.rawValue: "Smoky",
            HKWeatherCondition.dust.rawValue: "Dust",
            HKWeatherCondition.snow.rawValue: "Snow",
            HKWeatherCondition.hail.rawValue: "Hail",
            HKWeatherCondition.sleet.rawValue: "Sleet",
            HKWeatherCondition.freezingDrizzle.rawValue: "Freezing Drizzle",
            HKWeatherCondition.freezingRain.rawValue: "Freezing Rain",
            HKWeatherCondition.mixedRainAndHail.rawValue: "Mixed Rain And Hail",
            HKWeatherCondition.mixedRainAndSnow.rawValue: "Mixed Rain And Snow",
            HKWeatherCondition.mixedRainAndSleet.rawValue: "Mixed Rain And Sleet",
            HKWeatherCondition.mixedSnowAndSleet.rawValue: "Mixed Snow And Sleet",
            HKWeatherCondition.drizzle.rawValue: "Drizzle",
            HKWeatherCondition.scatteredShowers.rawValue: "Scattered Showers",
            HKWeatherCondition.showers.rawValue: "Showers",
            HKWeatherCondition.thunderstorms.rawValue: "Thunderstorms",
            HKWeatherCondition.tropicalStorm.rawValue: "Tropical Storm",
            HKWeatherCondition.hurricane.rawValue: "Hurricane",
            HKWeatherCondition.tornado.rawValue: "Tornado"
        ]),
        HKMetadataKeySwimmingLocationType: codings(HKWorkoutSwimmingLocationType.self, displays: [
            HKWorkoutSwimmingLocationType.unknown.rawValue: "Unknown",
            HKWorkoutSwimmingLocationType.pool.rawValue: "Pool",
            HKWorkoutSwimmingLocationType.openWater.rawValue: "Open Water"
        ])
    ]

    /// Encode SDK enumerations with their documentation systems and raw codes without truncating fractional numbers.
    static func metadataCoding(_ number: NSNumber, key: String) -> Coding? {
        guard let raw = Int(exactly: number.doubleValue), number.decimalValue == Decimal(raw) else {
            return nil
        }
        if #available(iOS 26, macOS 26, watchOS 26, *), key == HKMetadataKeyVO2MaxTestType,
           raw == HKVO2MaxTestType.predictionStepTest.rawValue {
            return codings(HKVO2MaxTestType.self, displays: [raw: "Prediction Step Test"])[raw]
        }
        return codingTables[key]?[raw]
    }

    private static func codings<Value>(_ type: Value.Type, displays: [Int: String]) -> [Int: Coding] {
        let url = "https://developer.apple.com/documentation/healthkit/" + String(describing: type).lowercased()
        let system = FHIRPrimitive(FHIRURI(stringLiteral: url))
        return Dictionary(uniqueKeysWithValues: displays.map { raw, display in
            (raw, Coding(code: String(raw).asFHIRStringPrimitive(), display: display.asFHIRStringPrimitive(), system: system))
        })
    }
}

#endif
