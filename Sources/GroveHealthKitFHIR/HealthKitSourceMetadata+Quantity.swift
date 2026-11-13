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
    private static let percentageCode = "%"

    static let knownQuantityCodes: [String: String] = [
        HKMetadataKeyWeatherTemperature: "Cel",
        HKMetadataKeyWeatherHumidity: percentageCode,
        HKMetadataKeyAlpineSlopeGrade: percentageCode,
        HKMetadataKeyHeartRateRecoveryActivityDuration: "s",
        HKMetadataKeyFitnessMachineDuration: "s",
        HKMetadataKeyAudioExposureDuration: "s",
        HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate: "/min",
        HKMetadataKeyHeartRateEventThreshold: "/min",
        HKMetadataKeyAverageSpeed: "m/s",
        HKMetadataKeyMaximumSpeed: "m/s",
        HKMetadataKeyElevationAscended: "m",
        HKMetadataKeyElevationDescended: "m",
        HKMetadataKeyIndoorBikeDistance: "m",
        HKMetadataKeyCrossTrainerDistance: "m",
        HKMetadataKeyAverageMETs: "kcal/(kg.h)",
        HKMetadataKeyAudioExposureLevel: "dB[SPL]",
        HKMetadataKeyHeadphoneGain: "dB[SPL]",
        HKMetadataKeyBarometricPressure: "mm[Hg]",
        HKMetadataKeyVO2MaxValue: "mL/kg/min",
        HKMetadataKeyLowCardioFitnessEventThreshold: "mL/kg/min",
        HKMetadataKeyMaximumLightIntensity: "lx"
    ]

    /// The fallback order is part of the metadata contract; HealthKit unit constructors live in the shared unit table.
    static let fallbackQuantityCodes = [
        "1", "/min", "s", "m", "m/s", "g", "L", "L/min", "kcal", "W", "Cel", "mm[Hg]", "mg/dL", "mL/kg/min",
        "kcal/(kg.h)", "[iU]", "S", "dB[SPL]", "dB", "lx"
    ]

    /// Known keys use their specified units. A custom key uses the first compatible canonical unit.
    static func metadataQuantity(_ quantity: HKQuantity, key: String, sample: HKSample) -> Quantity? {
        let binding: (unit: HKUnit, code: String)?
        if key == HKMetadataKeySessionEstimate {
            guard let sample = sample as? HKQuantitySample,
                  let type = HealthKitSourceType(sample.quantityType),
                  let unit = HealthKitContentPlan[type].unitBinding else {
                return nil
            }
            binding = (unit.unit, unit.ucumCode)
        } else if let code = knownQuantityCodes[key] {
            binding = HealthKitContentRules.ucumUnits[code].map { ($0, code) }
        } else {
            binding = fallbackQuantityCodes.lazy
                .compactMap { code in HealthKitContentRules.ucumUnits[code].map { (unit: $0, code: code) } }
                .first { quantity.is(compatibleWith: $0.unit) }
        }
        guard let binding, quantity.is(compatibleWith: binding.unit) else {
            return nil
        }
        let rawValue = quantity.doubleValue(for: binding.unit)
        let number = binding.code == percentageCode ? QuantityRead.percent(ofFraction: rawValue) : rawValue
        guard let value = try? GroveFHIRDecimal(number) else {
            return nil
        }
        return Quantity(
            code: binding.code.asFHIRStringPrimitive(),
            system: Canonicals.ucum,
            unit: binding.code.asFHIRStringPrimitive(),
            value: value.primitive
        )
    }
}

#endif
