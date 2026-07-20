//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import SpeziHealthKitFHIRMacros


@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKAppleECGAlgorithmVersion.self,
    .version1, .version2
)
extension HKAppleECGAlgorithmVersion: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKBloodGlucoseMealTime.self,
    .preprandial, .postprandial
)
extension HKBloodGlucoseMealTime: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKBodyTemperatureSensorLocation.self,
    .other, .armpit, .body, .ear, .finger, .gastroIntestinal,
    .mouth, .rectum, .toe, .earDrum, .temporalArtery, .forehead
)
extension HKBodyTemperatureSensorLocation: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCyclingFunctionalThresholdPowerTestType.self,
    .maxExercise60Minute, .maxExercise20Minute, .rampTest, .predictionExercise)
extension HKCyclingFunctionalThresholdPowerTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKDevicePlacementSide.self,
    .unknown, .left, .right, .central
)
extension HKDevicePlacementSide: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateMotionContext.self,
    .notSet, .sedentary, .active
)
extension HKHeartRateMotionContext: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateRecoveryTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise
)
extension HKHeartRateRecoveryTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateSensorLocation.self,
    .other, .chest, .wrist, .finger, .hand, .earLobe, .foot
)
extension HKHeartRateSensorLocation: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKInsulinDeliveryReason.self,
    .basal, .bolus
)
extension HKInsulinDeliveryReason: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKPhysicalEffortEstimationType.self,
    .activityLookup, .deviceSensed
)
extension HKPhysicalEffortEstimationType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKSwimmingStrokeStyle.self,
    .unknown, .mixed, .freestyle, .backstroke, .breaststroke, .butterfly, .kickboard
)
extension HKSwimmingStrokeStyle: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKUserMotionContext.self,
    .notSet, .stationary, .active
)
extension HKUserMotionContext: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKVO2MaxTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise,
    additionalCases: "predictionStepTest"
)
extension HKVO2MaxTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWaterSalinity.self,
    .freshWater, .saltWater
)
extension HKWaterSalinity: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWeatherCondition.self,
    .none, .clear, .fair, .partlyCloudy, .mostlyCloudy, .cloudy, .foggy, .haze,
    .windy, .blustery, .smoky, .dust, .snow, .hail, .sleet, .freezingDrizzle,
    .freezingRain, .mixedRainAndHail, .mixedRainAndSnow, .mixedRainAndSleet, .mixedSnowAndSleet,
    .drizzle, .scatteredShowers, .showers, .thunderstorms, .tropicalStorm, .hurricane, .tornado
)
extension HKWeatherCondition: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWorkoutSwimmingLocationType.self,
    .unknown, .pool, .openWater
)
extension HKWorkoutSwimmingLocationType: FHIRCodingConvertibleHKEnum {}

#endif
