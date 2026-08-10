//
// This source file is part of the Stanford Spezi open-source project
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
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKAppleECGAlgorithmVersion: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKBloodGlucoseMealTime.self,
    .preprandial, .postprandial
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKBloodGlucoseMealTime: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKBodyTemperatureSensorLocation.self,
    .other, .armpit, .body, .ear, .finger, .gastroIntestinal,
    .mouth, .rectum, .toe, .earDrum, .temporalArtery, .forehead
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKBodyTemperatureSensorLocation: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCyclingFunctionalThresholdPowerTestType.self,
    .maxExercise60Minute, .maxExercise20Minute, .rampTest, .predictionExercise)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCyclingFunctionalThresholdPowerTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKDevicePlacementSide.self,
    .unknown, .left, .right, .central
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKDevicePlacementSide: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateMotionContext.self,
    .notSet, .sedentary, .active
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHeartRateMotionContext: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateRecoveryTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHeartRateRecoveryTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKHeartRateSensorLocation.self,
    .other, .chest, .wrist, .finger, .hand, .earLobe, .foot
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHeartRateSensorLocation: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKInsulinDeliveryReason.self,
    .basal, .bolus
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKInsulinDeliveryReason: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKPhysicalEffortEstimationType.self,
    .activityLookup, .deviceSensed
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKPhysicalEffortEstimationType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKSwimmingStrokeStyle.self,
    .unknown, .mixed, .freestyle, .backstroke, .breaststroke, .butterfly, .kickboard
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKSwimmingStrokeStyle: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKUserMotionContext.self,
    .notSet, .stationary, .active
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKUserMotionContext: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKVO2MaxTestType.self,
    .maxExercise, .predictionSubMaxExercise, .predictionNonExercise,
    additionalCases: "predictionStepTest"
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKVO2MaxTestType: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWaterSalinity.self,
    .freshWater, .saltWater
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKWaterSalinity: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWeatherCondition.self,
    .none, .clear, .fair, .partlyCloudy, .mostlyCloudy, .cloudy, .foggy, .haze,
    .windy, .blustery, .smoky, .dust, .snow, .hail, .sleet, .freezingDrizzle,
    .freezingRain, .mixedRainAndHail, .mixedRainAndSnow, .mixedRainAndSleet, .mixedSnowAndSleet,
    .drizzle, .scatteredShowers, .showers, .thunderstorms, .tropicalStorm, .hurricane, .tornado
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKWeatherCondition: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKWorkoutSwimmingLocationType.self,
    .unknown, .pool, .openWater
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKWorkoutSwimmingLocationType: FHIRCodingConvertibleHKEnum {}

#endif
