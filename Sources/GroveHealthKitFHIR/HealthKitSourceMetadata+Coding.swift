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
            HKAppleECGAlgorithmVersion.version1: "Version 1",
            HKAppleECGAlgorithmVersion.version2: "Version 2"
        ]),
        HKMetadataKeyBloodGlucoseMealTime: codings(HKBloodGlucoseMealTime.self, displays: [
            HKBloodGlucoseMealTime.preprandial: "Preprandial",
            HKBloodGlucoseMealTime.postprandial: "Postprandial"
        ]),
        HKMetadataKeyBodyTemperatureSensorLocation: codings(HKBodyTemperatureSensorLocation.self, displays: [
            HKBodyTemperatureSensorLocation.other: "Other",
            HKBodyTemperatureSensorLocation.armpit: "Armpit",
            HKBodyTemperatureSensorLocation.body: "Body",
            HKBodyTemperatureSensorLocation.ear: "Ear",
            HKBodyTemperatureSensorLocation.finger: "Finger",
            HKBodyTemperatureSensorLocation.gastroIntestinal: "Gastro Intestinal",
            HKBodyTemperatureSensorLocation.mouth: "Mouth",
            HKBodyTemperatureSensorLocation.rectum: "Rectum",
            HKBodyTemperatureSensorLocation.toe: "Toe",
            HKBodyTemperatureSensorLocation.earDrum: "Ear Drum",
            HKBodyTemperatureSensorLocation.temporalArtery: "Temporal Artery",
            HKBodyTemperatureSensorLocation.forehead: "Forehead"
        ]),
        HKMetadataKeyCyclingFunctionalThresholdPowerTestType: codings(HKCyclingFunctionalThresholdPowerTestType.self, displays: [
            HKCyclingFunctionalThresholdPowerTestType.maxExercise60Minute: "Max Exercise 60Minute",
            HKCyclingFunctionalThresholdPowerTestType.maxExercise20Minute: "Max Exercise 20Minute",
            HKCyclingFunctionalThresholdPowerTestType.rampTest: "Ramp Test",
            HKCyclingFunctionalThresholdPowerTestType.predictionExercise: "Prediction Exercise"
        ]),
        HKMetadataKeyDevicePlacementSide: codings(HKDevicePlacementSide.self, displays: [
            HKDevicePlacementSide.unknown: "Unknown",
            HKDevicePlacementSide.left: "Left",
            HKDevicePlacementSide.right: "Right",
            HKDevicePlacementSide.central: "Central"
        ]),
        HKMetadataKeyHeartRateMotionContext: codings(HKHeartRateMotionContext.self, displays: [
            HKHeartRateMotionContext.notSet: "Not Set",
            HKHeartRateMotionContext.sedentary: "Sedentary",
            HKHeartRateMotionContext.active: "Active"
        ]),
        HKMetadataKeyHeartRateRecoveryTestType: codings(HKHeartRateRecoveryTestType.self, displays: [
            HKHeartRateRecoveryTestType.maxExercise: "Max Exercise",
            HKHeartRateRecoveryTestType.predictionSubMaxExercise: "Prediction Sub Max Exercise",
            HKHeartRateRecoveryTestType.predictionNonExercise: "Prediction Non Exercise"
        ]),
        HKMetadataKeyHeartRateSensorLocation: codings(HKHeartRateSensorLocation.self, displays: [
            HKHeartRateSensorLocation.other: "Other",
            HKHeartRateSensorLocation.chest: "Chest",
            HKHeartRateSensorLocation.wrist: "Wrist",
            HKHeartRateSensorLocation.finger: "Finger",
            HKHeartRateSensorLocation.hand: "Hand",
            HKHeartRateSensorLocation.earLobe: "Ear Lobe",
            HKHeartRateSensorLocation.foot: "Foot"
        ]),
        HKMetadataKeyInsulinDeliveryReason: codings(HKInsulinDeliveryReason.self, displays: [
            HKInsulinDeliveryReason.basal: "Basal",
            HKInsulinDeliveryReason.bolus: "Bolus"
        ]),
        HKMetadataKeyPhysicalEffortEstimationType: codings(HKPhysicalEffortEstimationType.self, displays: [
            HKPhysicalEffortEstimationType.activityLookup: "Activity Lookup",
            HKPhysicalEffortEstimationType.deviceSensed: "Device Sensed"
        ]),
        HKMetadataKeySwimmingStrokeStyle: codings(HKSwimmingStrokeStyle.self, displays: [
            HKSwimmingStrokeStyle.unknown: "Unknown",
            HKSwimmingStrokeStyle.mixed: "Mixed",
            HKSwimmingStrokeStyle.freestyle: "Freestyle",
            HKSwimmingStrokeStyle.backstroke: "Backstroke",
            HKSwimmingStrokeStyle.breaststroke: "Breaststroke",
            HKSwimmingStrokeStyle.butterfly: "Butterfly",
            HKSwimmingStrokeStyle.kickboard: "Kickboard"
        ]),
        HKMetadataKeyUserMotionContext: codings(HKUserMotionContext.self, displays: [
            HKUserMotionContext.notSet: "Not Set",
            HKUserMotionContext.stationary: "Stationary",
            HKUserMotionContext.active: "Active"
        ]),
        HKMetadataKeyVO2MaxTestType: codings(HKVO2MaxTestType.self, displays: [
            HKVO2MaxTestType.maxExercise: "Max Exercise",
            HKVO2MaxTestType.predictionSubMaxExercise: "Prediction Sub Max Exercise",
            HKVO2MaxTestType.predictionNonExercise: "Prediction Non Exercise"
        ]),
        HKMetadataKeyWaterSalinity: codings(HKWaterSalinity.self, displays: [
            HKWaterSalinity.freshWater: "Fresh Water",
            HKWaterSalinity.saltWater: "Salt Water"
        ]),
        HKMetadataKeyWeatherCondition: codings(HKWeatherCondition.self, displays: [
            HKWeatherCondition.none: "None",
            HKWeatherCondition.clear: "Clear",
            HKWeatherCondition.fair: "Fair",
            HKWeatherCondition.partlyCloudy: "Partly Cloudy",
            HKWeatherCondition.mostlyCloudy: "Mostly Cloudy",
            HKWeatherCondition.cloudy: "Cloudy",
            HKWeatherCondition.foggy: "Foggy",
            HKWeatherCondition.haze: "Haze",
            HKWeatherCondition.windy: "Windy",
            HKWeatherCondition.blustery: "Blustery",
            HKWeatherCondition.smoky: "Smoky",
            HKWeatherCondition.dust: "Dust",
            HKWeatherCondition.snow: "Snow",
            HKWeatherCondition.hail: "Hail",
            HKWeatherCondition.sleet: "Sleet",
            HKWeatherCondition.freezingDrizzle: "Freezing Drizzle",
            HKWeatherCondition.freezingRain: "Freezing Rain",
            HKWeatherCondition.mixedRainAndHail: "Mixed Rain And Hail",
            HKWeatherCondition.mixedRainAndSnow: "Mixed Rain And Snow",
            HKWeatherCondition.mixedRainAndSleet: "Mixed Rain And Sleet",
            HKWeatherCondition.mixedSnowAndSleet: "Mixed Snow And Sleet",
            HKWeatherCondition.drizzle: "Drizzle",
            HKWeatherCondition.scatteredShowers: "Scattered Showers",
            HKWeatherCondition.showers: "Showers",
            HKWeatherCondition.thunderstorms: "Thunderstorms",
            HKWeatherCondition.tropicalStorm: "Tropical Storm",
            HKWeatherCondition.hurricane: "Hurricane",
            HKWeatherCondition.tornado: "Tornado"
        ]),
        HKMetadataKeySwimmingLocationType: codings(HKWorkoutSwimmingLocationType.self, displays: [
            HKWorkoutSwimmingLocationType.unknown: "Unknown",
            HKWorkoutSwimmingLocationType.pool: "Pool",
            HKWorkoutSwimmingLocationType.openWater: "Open Water"
        ])
    ]

    /// Encode SDK enumerations with their documentation systems and raw codes without truncating fractional numbers.
    static func metadataCoding(_ number: NSNumber, key: String) -> Coding? {
        guard let raw = Int(exactly: number.doubleValue), number.decimalValue == Decimal(raw) else {
            return nil
        }
        if #available(iOS 26, macOS 26, watchOS 26, *), key == HKMetadataKeyVO2MaxTestType,
           raw == HKVO2MaxTestType.predictionStepTest.rawValue {
            return codings(HKVO2MaxTestType.self, displays: [.predictionStepTest: "Prediction Step Test"])[raw]
        }
        return codingTables[key]?[raw]
    }

    private static func codings<Value: RawRepresentable & Hashable>(
        _ type: Value.Type,
        displays: [Value: String]
    ) -> [Int: Coding] where Value.RawValue == Int {
        let url = "https://developer.apple.com/documentation/healthkit/" + String(describing: type).lowercased()
        let system = FHIRPrimitive(FHIRURI(stringLiteral: url))
        return Dictionary(uniqueKeysWithValues: displays.map { value, display in
            (value.rawValue, Coding(code: String(value.rawValue).asFHIRStringPrimitive(), display: display.asFHIRStringPrimitive(), system: system))
        })
    }
}

#endif
