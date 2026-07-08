//
// This source file is part of the HealthKitOnFHIR open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import HealthKitOnFHIRMacros


@SynthesizeDisplayProperty(
    HKAppleECGAlgorithmVersion.self,
    .version1, .version2
)
@available(macOS 13, *)
extension HKAppleECGAlgorithmVersion: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKBloodGlucoseMealTime.self,
    .preprandial, .postprandial
)
@available(macOS 13, *)
extension HKBloodGlucoseMealTime: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKBodyTemperatureSensorLocation.self,
    .other, .armpit, .body, .ear, .finger, .gastroIntestinal,
    .mouth, .rectum, .toe, .earDrum, .temporalArtery, .forehead
)
@available(macOS 13, *)
extension HKBodyTemperatureSensorLocation: FHIRCodingConvertibleHKEnum {}

@available(iOS 17, macOS 14, watchOS 10, *)
@SynthesizeDisplayProperty(
    HKCyclingFunctionalThresholdPowerTestType.self,
    .maxExercise60Minute, .maxExercise20Minute, .rampTest, .predictionExercise)
@available(macOS 13, *)
extension HKCyclingFunctionalThresholdPowerTestType: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKDevicePlacementSide.self,
    .unknown, .left, .right, .central
)
@available(macOS 13, *)
extension HKDevicePlacementSide: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKHeartRateMotionContext.self,
    .notSet, .sedentary, .active
)
@available(macOS 13, *)
extension HKHeartRateMotionContext: FHIRCodingConvertibleHKEnum {}

@available(iOS 16, macOS 13, watchOS 9, *)
@SynthesizeDisplayProperty(
    HKHeartRateRecoveryTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise
)
@available(macOS 13, *)
extension HKHeartRateRecoveryTestType: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKHeartRateSensorLocation.self,
    .other, .chest, .wrist, .finger, .hand, .earLobe, .foot
)
@available(macOS 13, *)
extension HKHeartRateSensorLocation: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKInsulinDeliveryReason.self,
    .basal, .bolus
)
@available(macOS 13, *)
extension HKInsulinDeliveryReason: FHIRCodingConvertibleHKEnum {}

@available(iOS 17, macOS 14, watchOS 10, *)
@SynthesizeDisplayProperty(
    HKPhysicalEffortEstimationType.self,
    .activityLookup, .deviceSensed
)
@available(macOS 13, *)
extension HKPhysicalEffortEstimationType: FHIRCodingConvertibleHKEnum {}

@available(iOS 16, macOS 13, watchOS 9, *)
@SynthesizeDisplayProperty(
    HKSwimmingStrokeStyle.self,
    .unknown, .mixed, .freestyle, .backstroke, .breaststroke, .butterfly, .kickboard
)
@available(macOS 13, *)
extension HKSwimmingStrokeStyle: FHIRCodingConvertibleHKEnum {}

@available(iOS 16, macOS 13, watchOS 9, *)
@SynthesizeDisplayProperty(
    HKUserMotionContext.self,
    .notSet, .stationary, .active
)
@available(macOS 13, *)
extension HKUserMotionContext: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKVO2MaxTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise,
    additionalCases: "predictionStepTest"
)
@available(macOS 13, *)
extension HKVO2MaxTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 17, macOS 14, watchOS 10, *)
@SynthesizeDisplayProperty(
    HKWaterSalinity.self,
    .freshWater, .saltWater
)
@available(macOS 13, *)
extension HKWaterSalinity: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKWeatherCondition.self,
    .none, .clear, .fair, .partlyCloudy, .mostlyCloudy, .cloudy, .foggy, .haze,
    .windy, .blustery, .smoky, .dust, .snow, .hail, .sleet, .freezingDrizzle,
    .freezingRain, .mixedRainAndHail, .mixedRainAndSnow, .mixedRainAndSleet, .mixedSnowAndSleet,
    .drizzle, .scatteredShowers, .showers, .thunderstorms, .tropicalStorm, .hurricane, .tornado
)
@available(macOS 13, *)
extension HKWeatherCondition: FHIRCodingConvertibleHKEnum {}

@SynthesizeDisplayProperty(
    HKWorkoutSwimmingLocationType.self,
    .unknown, .pool, .openWater
)
@available(macOS 13, *)
extension HKWorkoutSwimmingLocationType: FHIRCodingConvertibleHKEnum {}
