//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import Testing


/// Pins the metadata-key codes Grove publishes to the raw values HealthKit hands out.
///
/// This suite guards the Apple side: a raw value the platform changes under a constant
/// Grove already writes. The guide side — the same codes appearing in
/// `platforms/input/fsh/key-spaces.fsh` — is checked by
/// `tools/generate-platform-vocabulary.py --check-metadata-keys` in the grove-fhir
/// workspace, which reads the list below out of ``PlatformVocabularyDumpTests``; a
/// literal typed here cannot pin a file in another repository.
@Suite
struct MetadataKeyVocabularyTests {
    /// HealthKit's metadata-key constants and their raw values disagree more often than
    /// not — `HKMetadataKeyTimeZone` is `"HKTimeZone"`, `HKMetadataKeyAverageSpeed` is
    /// `"HKAverageSpeed"`, and `HKMetadataKeyCyclingFunctionalThresholdPowerTestType`
    /// carries a doubled word Apple shipped by mistake. Grove writes the raw value, so
    /// the published vocabulary lists the raw value.
    static let publishedKeys: [(constant: String, code: String)] = [
        (HKMetadataKeyAlpineSlopeGrade, "HKAlpineSlopeGrade"),
        (HKMetadataKeyAppleECGAlgorithmVersion, "HKMetadataKeyAppleECGAlgorithmVersion"),
        (HKMetadataKeyAudioExposureDuration, "HKMetadataKeyAudioExposureDuration"),
        (HKMetadataKeyAudioExposureLevel, "HKMetadataKeyAudioExposureLevel"),
        (HKMetadataKeyAverageMETs, "HKAverageMETs"),
        (HKMetadataKeyAverageSpeed, "HKAverageSpeed"),
        (HKMetadataKeyBarometricPressure, "HKMetadataKeyBarometricPressure"),
        (HKMetadataKeyBloodGlucoseMealTime, "HKBloodGlucoseMealTime"),
        (HKMetadataKeyBodyTemperatureSensorLocation, "HKBodyTemperatureSensorLocation"),
        (HKMetadataKeyCrossTrainerDistance, "HKCrossTrainerDistance"),
        (HKMetadataKeyCyclingFunctionalThresholdPowerTestType, "HKCyclingCyclingFunctionalThresholdPowerTestType"),
        (HKMetadataKeyDevicePlacementSide, "HKMetadataKeyDevicePlacementSide"),
        (HKMetadataKeyElevationAscended, "HKElevationAscended"),
        (HKMetadataKeyElevationDescended, "HKElevationDescended"),
        (HKMetadataKeyExternalUUID, "HKExternalUUID"),
        (HKMetadataKeyFitnessMachineDuration, "HKFitnessMachineDuration"),
        (HKMetadataKeyHeadphoneGain, "HKMetadataKeyHeadphoneGain"),
        (HKMetadataKeyHeartRateEventThreshold, "HKHeartRateEventThreshold"),
        (HKMetadataKeyHeartRateMotionContext, "HKMetadataKeyHeartRateMotionContext"),
        (HKMetadataKeyHeartRateRecoveryActivityDuration, "HKMetadataKeyHeartRateRecoveryActivityDuration"),
        (HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate, "HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate"),
        (HKMetadataKeyHeartRateRecoveryTestType, "HKMetadataKeyHeartRateRecoveryTestType"),
        (HKMetadataKeyHeartRateSensorLocation, "HKHeartRateSensorLocation"),
        (HKMetadataKeyIndoorBikeDistance, "HKIndoorBikeDistance"),
        (HKMetadataKeyInsulinDeliveryReason, "HKInsulinDeliveryReason"),
        (HKMetadataKeyLowCardioFitnessEventThreshold, "HKLowCardioFitnessEventThreshold"),
        (HKMetadataKeyMaximumLightIntensity, "HKMetadataKeyMaximumLightIntensity"),
        (HKMetadataKeyMaximumSpeed, "HKMaximumSpeed"),
        (HKMetadataKeyMenstrualCycleStart, "HKMenstrualCycleStart"),
        (HKMetadataKeyPhysicalEffortEstimationType, "HKPhysicalEffortEstimationType"),
        (HKMetadataKeySessionEstimate, "HKMetadataKeySessionEstimate"),
        (HKMetadataKeySexualActivityProtectionUsed, "HKSexualActivityProtectionUsed"),
        (HKMetadataKeySwimmingLocationType, "HKSwimmingLocationType"),
        (HKMetadataKeySwimmingStrokeStyle, "HKSwimmingStrokeStyle"),
        (HKMetadataKeyTimeZone, "HKTimeZone"),
        (HKMetadataKeyUserMotionContext, "HKMetadataKeyUserMotionContext"),
        (HKMetadataKeyVO2MaxTestType, "HKVO2MaxTestType"),
        (HKMetadataKeyVO2MaxValue, "HKVO2MaxValue"),
        (HKMetadataKeyWasUserEntered, "HKWasUserEntered"),
        (HKMetadataKeyWaterSalinity, "HKMetadataKeyWaterSalinity"),
        (HKMetadataKeyWeatherCondition, "HKWeatherCondition"),
        (HKMetadataKeyWeatherHumidity, "HKWeatherHumidity"),
        (HKMetadataKeyWeatherTemperature, "HKWeatherTemperature")
    ]

    @Test
    func applesRawValuesAreUnchanged() {
        for (constant, code) in Self.publishedKeys {
            #expect(constant == code, "the published code must match the framework's raw value")
        }
    }
}

#endif
