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
    private static let knownQuantityUnits: [String: (unit: HKUnit, code: String)] = [
        HKMetadataKeyWeatherTemperature: (.degreeCelsius(), "Cel"),
        HKMetadataKeyWeatherHumidity: (.percent(), "%"),
        HKMetadataKeyAlpineSlopeGrade: (.percent(), "%"),
        HKMetadataKeyHeartRateRecoveryActivityDuration: (.second(), "s"),
        HKMetadataKeyFitnessMachineDuration: (.second(), "s"),
        HKMetadataKeyAudioExposureDuration: (.second(), "s"),
        HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate: (.count().unitDivided(by: .minute()), "/min"),
        HKMetadataKeyHeartRateEventThreshold: (.count().unitDivided(by: .minute()), "/min"),
        HKMetadataKeyAverageSpeed: (.meter().unitDivided(by: .second()), "m/s"),
        HKMetadataKeyMaximumSpeed: (.meter().unitDivided(by: .second()), "m/s"),
        HKMetadataKeyElevationAscended: (.meter(), "m"),
        HKMetadataKeyElevationDescended: (.meter(), "m"),
        HKMetadataKeyIndoorBikeDistance: (.meter(), "m"),
        HKMetadataKeyCrossTrainerDistance: (.meter(), "m"),
        HKMetadataKeyAverageMETs: (.largeCalorie().unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .hour())), "kcal/(kg.h)"),
        HKMetadataKeyAudioExposureLevel: (.decibelAWeightedSoundPressureLevel(), "dB[SPL]"),
        HKMetadataKeyHeadphoneGain: (.decibelAWeightedSoundPressureLevel(), "dB[SPL]"),
        HKMetadataKeyBarometricPressure: (.millimeterOfMercury(), "mm[Hg]"),
        HKMetadataKeyVO2MaxValue: (oxygenVolumeUnit, "mL/kg/min"),
        HKMetadataKeyLowCardioFitnessEventThreshold: (oxygenVolumeUnit, "mL/kg/min"),
        HKMetadataKeyMaximumLightIntensity: (.lux(), "lx")
    ]

    private static let oxygenVolumeUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    private static let fallbackQuantityUnits: [(unit: HKUnit, code: String)] = [
        (.count(), "1"),
        (.count().unitDivided(by: .minute()), "/min"),
        (.second(), "s"),
        (.meter(), "m"),
        (.meter().unitDivided(by: .second()), "m/s"),
        (.gram(), "g"),
        (.liter(), "L"),
        (.liter().unitDivided(by: .minute()), "L/min"),
        (.largeCalorie(), "kcal"),
        (.watt(), "W"),
        (.degreeCelsius(), "Cel"),
        (.millimeterOfMercury(), "mm[Hg]"),
        (.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), "mg/dL"),
        (.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute())), "mL/kg/min"),
        (.largeCalorie().unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .hour())), "kcal/(kg.h)"),
        (.internationalUnit(), "[iU]"),
        (.siemen(), "S"),
        (.decibelAWeightedSoundPressureLevel(), "dB[SPL]"),
        (.decibelHearingLevel(), "dB"),
        (.lux(), "lx")
    ]

    /// Known keys retain their legacy units. A custom key uses the first compatible canonical unit.
    static func metadataQuantity(_ quantity: HKQuantity, key: String, sample: HKSample) -> Quantity? {
        let binding: (unit: HKUnit, code: String)?
        if key == HKMetadataKeySessionEstimate {
            guard let sample = sample as? HKQuantitySample,
                  let type = HealthKitSourceType(sample.quantityType),
                  let unit = HealthKitContentPlan[type].unitBinding else {
                return nil
            }
            binding = (unit.unit, unit.ucumCode)
        } else if let known = knownQuantityUnits[key] {
            binding = known
        } else {
            binding = fallbackQuantityUnits.first { quantity.is(compatibleWith: $0.unit) }
        }
        guard let binding, quantity.is(compatibleWith: binding.unit) else {
            return nil
        }
        let number = quantity.doubleValue(for: binding.unit) * (binding.code == "%" ? 100 : 1)
        guard let value = try? GroveFHIRDecimal(number) else {
            return nil
        }
        return Quantity(
            code: binding.code.asFHIRStringPrimitive(),
            system: "http://unitsofmeasure.org",
            unit: binding.code.asFHIRStringPrimitive(),
            value: value.primitive
        )
    }
}

#endif
