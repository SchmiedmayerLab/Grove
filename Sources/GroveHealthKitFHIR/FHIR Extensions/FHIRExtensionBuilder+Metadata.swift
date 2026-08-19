//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

#if canImport(HealthKit)

public import FHIRModelsExtensions
import Foundation
import GroveHealthKit
import GroveLegacyIdentifiers
public import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionURL {
    /// Url of a FHIR Extension carrying one entry of a HealthKit sample's metadata dictionary.
    ///
    /// One extension per entry, each with a `key` coding and a typed `value` — a
    /// platform key cannot become part of the extension URL, since every extension URL
    /// must resolve to a StructureDefinition.
    public static let metadata = Self(
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-platform-metadata",
        superseding: SupersededFHIRURLs.metadata
    )
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionBuilderProtocol where Self == FHIRExtensionBuilder<HKObject> {
    /// A FHIR Extension Builder that writes encoded metadata of a HealthKit sample into a FHIR `Observation` created from the sample.
    ///
    /// - parameter promotedKeys: Metadata keys the conversion has already promoted to Layer-3 components.
    ///     Layer 4 carries whatever survives layers 1–3, so these must not be written a second time.
    public static func metadata(excluding promotedKeys: Set<String> = []) -> FHIRExtensionBuilder<HKObject> {
        .init { (object: HKObject, resource) in
            // Keys with first-class FHIR homes are routed there by the conversion
            // (timezone extension on effective[x], grove-recording-method) and must
            // not be duplicated into the metadata envelope.
            let routedKeys = promotedKeys.union([HKMetadataKeyTimeZone, HKMetadataKeyWasUserEntered])
            resource.removeAllExtensions(withUrl: .metadata)
            guard let metadata = object.metadata?.filter({ !routedKeys.contains($0.key) }), !metadata.isEmpty else {
                return
            }
            // Sorted, so the same sample always yields the same extension order.
            for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                guard let extensionValue = try Self.extensionValue(for: value, forKey: key, of: object) else {
                    continue
                }
                var entry = Extension(url: .metadata)
                entry.extension = [
                    Extension(
                        url: "key",
                        value: .coding(Coding(
                            code: key.asFHIRStringPrimitive(),
                            system: GroveFHIRVocabulary.healthKitMetadataKey
                        ))
                    ),
                    Extension(url: "value", value: extensionValue)
                ]
                resource.append(extension: entry, behaviour: .additive)
            }
        }
    }

    /// The `value[x]` one metadata entry is written as, or nil when the entry has no FHIR spelling.
    ///
    /// The HKObject docs state that "Keys must be NSString and values must be either NSString, NSNumber, NSDate, or HKQuantity".
    /// Additionally, there are some HKMetadataKey constants which say that they store a BOOL, so we support that as well.
    private static func extensionValue(for value: Any, forKey key: String, of object: HKObject) throws -> Extension.ValueX? {
        switch value {
        case let value as String:
            return .string(value.asFHIRStringPrimitive())
        case let value as NSNumber:
            return Self.numberValue(value, forKey: key)
        case let value as Date:
            return .dateTime(FHIRPrimitive(try DateTime(date: value)))
        case let value as Bool:
            return .boolean(value.asPrimitive())
        case let value as HKQuantity:
            return try Self.quantityValue(value, forKey: key, of: object)
        default:
            print("Encountered unexpected HKSample metadata value of type \(Swift.type(of: value)), for key '\(key)'. Skipping.")
            return nil
        }
    }

    private static func numberValue(_ value: NSNumber, forKey key: String) -> Extension.ValueX {
        if let type = Self.type(forMetadataKey: key), let value = type.init(rawValue: value.intValue) {
            return .coding(value.asCoding)
        }
        @_transparent
        func typeEncoding(_ type: (some Any).Type) -> String {
            String(cString: _getObjCTypeEncoding(type))
        }
        switch String(cString: value.objCType) {
        case "c" where value.intValue == 0 || value.intValue == 1:
            // if the number reports as a char (int8), and it's value is 0 or 1, we treat it as a boolean value.
            // we need to do this as ObjC bools are encoded as chars.
            // the likelihood of a HKSample containing an int8-typed metadata entry that is actually supposed to be a
            // numeric value is significantly lower than the sample containing a boolean-typed metadata value
            // originating from ObjC.
            fallthrough // swiftlint:disable:this no_fallthrough_only
        case typeEncoding(Bool.self), typeEncoding(ObjCBool.self):
            return .boolean(value.boolValue.asPrimitive())
        default:
            return .decimal(FHIRPrimitive(FHIRDecimal(value.decimalValue)))
        }
    }

    private static func quantityValue(_ value: HKQuantity, forKey key: String, of object: HKObject) throws -> Extension.ValueX? {
        if key == HKMetadataKeySessionEstimate {
            guard let sample = object as? HKQuantitySample,
                  let sampleType = SampleType(sample.quantityType),
                  let mapping = QuantityTypesFHIRMapping.default[sampleType] else {
                return nil // should be unreachable. skipping
            }
            return .quantity(try value.buildQuantity(mapping: mapping))
        }
        guard let mapping = QuantityTypeFHIRMapping.byMetadataKey[key] else {
            print("Encountered unexpected HKQuantity metadata value for key '\(key)'. Skipping.")
            return nil
        }
        return .quantity(try value.buildQuantity(mapping: mapping))
    }

    private static func type(forMetadataKey key: String) -> (any FHIRCodingConvertibleHKEnum.Type)? { // swiftlint:disable:this cyclomatic_complexity
        switch key {
        case HKMetadataKeyAppleECGAlgorithmVersion:
            HKAppleECGAlgorithmVersion.self
        case HKMetadataKeyBloodGlucoseMealTime:
            HKBloodGlucoseMealTime.self
        case HKMetadataKeyBodyTemperatureSensorLocation:
            HKBodyTemperatureSensorLocation.self
        case HKMetadataKeyCyclingFunctionalThresholdPowerTestType:
            HKCyclingFunctionalThresholdPowerTestType.self
        case HKMetadataKeyDevicePlacementSide:
            HKDevicePlacementSide.self
        case HKMetadataKeyHeartRateMotionContext:
            HKHeartRateMotionContext.self
        case HKMetadataKeyHeartRateRecoveryTestType:
            HKHeartRateRecoveryTestType.self
        case HKMetadataKeyHeartRateSensorLocation:
            HKHeartRateSensorLocation.self
        case HKMetadataKeyInsulinDeliveryReason:
            HKInsulinDeliveryReason.self
        case HKMetadataKeyPhysicalEffortEstimationType:
            HKPhysicalEffortEstimationType.self
        case HKMetadataKeySwimmingStrokeStyle:
            HKSwimmingStrokeStyle.self
        case HKMetadataKeyUserMotionContext:
            HKUserMotionContext.self
        case HKMetadataKeyVO2MaxTestType:
            HKVO2MaxTestType.self
        case HKMetadataKeyWaterSalinity:
            HKWaterSalinity.self
        case HKMetadataKeyWeatherCondition:
            HKWeatherCondition.self
        case HKMetadataKeySwimmingLocationType:
            HKWorkoutSwimmingLocationType.self
        default:
            nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuantityTypeFHIRMapping {
    /// `HKMetadataKeySessionEstimate` is deliberately absent: its value carries the sample's own
    /// unit, so it is written with the sample's mapping rather than one of its own.
    fileprivate static let byMetadataKey: [String: QuantityTypeFHIRMapping] = [
        HKMetadataKeyWeatherTemperature: .weatherTemperature,
        HKMetadataKeyWeatherHumidity: .weatherHumidity,
        HKMetadataKeyHeartRateRecoveryActivityDuration: .heartRateRecoveryActivityDuration,
        HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate: .heartRateRecoveryMaxObservedRecoveryHeartRate,
        HKMetadataKeyAverageSpeed: .averageSpeed,
        HKMetadataKeyMaximumSpeed: .maximumSpeed,
        HKMetadataKeyAlpineSlopeGrade: .alpineSlopeGrade,
        HKMetadataKeyElevationAscended: .elevationAscended,
        HKMetadataKeyElevationDescended: .elevationDescended,
        HKMetadataKeyFitnessMachineDuration: .fitnessMachineDuration,
        HKMetadataKeyIndoorBikeDistance: .indoorBikeDistance,
        HKMetadataKeyCrossTrainerDistance: .crossTrainerDistance,
        HKMetadataKeyHeartRateEventThreshold: .highHeartRateEventThreshold,
        HKMetadataKeyAverageMETs: .averageMETs,
        HKMetadataKeyAudioExposureLevel: .audioExposureLevel,
        HKMetadataKeyAudioExposureDuration: .audioExposureDuration,
        HKMetadataKeyBarometricPressure: .barometricPressure,
        HKMetadataKeyVO2MaxValue: .vo2MaxValue,
        HKMetadataKeyLowCardioFitnessEventThreshold: .lowCardioFitnessEventThreshold,
        HKMetadataKeyHeadphoneGain: .headphoneGain,
        HKMetadataKeyMaximumLightIntensity: .maximumLightIntensity
    ]

    fileprivate static let weatherTemperature = Self(
        codings: [
            Coding(
                code: HKMetadataKeyWeatherTemperature.asFHIRStringPrimitive(),
                display: "Weather Temperature",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .degreeCelsius(),
            unit: "C",
            system: .unitsOfMeasureSystem,
            code: "Cel"
        )
    )
    
    fileprivate static let weatherHumidity = Self(
        codings: [
            Coding(
                code: HKMetadataKeyWeatherHumidity.asFHIRStringPrimitive(),
                display: "Weather Humidity",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .percent(),
            unit: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
    )
    
    fileprivate static let heartRateRecoveryActivityDuration = Self(
        codings: [
            Coding(
                code: HKMetadataKeyHeartRateRecoveryActivityDuration.asFHIRStringPrimitive(),
                display: "Heart Rate Recovery Activity Duration",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .second(),
            unit: "s",
            system: .unitsOfMeasureSystem,
            code: "s"
        )
    )
    
    fileprivate static let heartRateRecoveryMaxObservedRecoveryHeartRate = Self( // swiftlint:disable:this identifier_name
        codings: [
            Coding(
                code: HKMetadataKeyHeartRateRecoveryMaxObservedRecoveryHeartRate.asFHIRStringPrimitive(),
                display: "Heart Rate Recovery Max Observed Recovery Heart Rate",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            ),
            Coding(
                code: "8867-4",
                display: "Heart rate",
                system: .loincSystem
            ),
            Coding(
                code: "364075005",
                display: "Heart rate",
                system: .snomedCT
            )
        ],
        unit: Unit(
            hkUnit: .count().unitDivided(by: .minute()),
            unit: "beats/minute",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
    )
    
    fileprivate static let averageSpeed = Self(
        codings: [
            Coding(
                code: HKMetadataKeyAverageSpeed.asFHIRStringPrimitive(),
                display: "Average Speed",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter().unitDivided(by: .second()),
            unit: "m/sec",
            system: .unitsOfMeasureSystem,
            code: "m/s"
        )
    )
    
    fileprivate static let maximumSpeed = Self(
        codings: [
            Coding(
                code: HKMetadataKeyMaximumSpeed.asFHIRStringPrimitive(),
                display: "Maximum Speed",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter().unitDivided(by: .second()),
            unit: "m/sec",
            system: .unitsOfMeasureSystem,
            code: "m/s"
        )
    )
    
    fileprivate static let alpineSlopeGrade = Self(
        codings: [
            Coding(
                code: HKMetadataKeyAlpineSlopeGrade.asFHIRStringPrimitive(),
                display: "Alpine Slope Grade",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .percent(),
            unit: "%",
            system: .unitsOfMeasureSystem,
            code: "%"
        )
    )
    
    fileprivate static let elevationAscended = Self(
        codings: [
            Coding(
                code: HKMetadataKeyElevationAscended.asFHIRStringPrimitive(),
                display: "Elevation Ascended",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter(),
            unit: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
    )
    
    fileprivate static let elevationDescended = Self(
        codings: [
            Coding(
                code: HKMetadataKeyElevationDescended.asFHIRStringPrimitive(),
                display: "Elevation Descended",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter(),
            unit: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
    )
    
    fileprivate static let fitnessMachineDuration = Self(
        codings: [
            Coding(
                code: HKMetadataKeyFitnessMachineDuration.asFHIRStringPrimitive(),
                display: "Fitness Machine Duration",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .second(),
            unit: "s",
            system: .unitsOfMeasureSystem,
            code: "s"
        )
    )
    
    fileprivate static let indoorBikeDistance = Self(
        codings: [
            Coding(
                code: HKMetadataKeyIndoorBikeDistance.asFHIRStringPrimitive(),
                display: "Indoor Bike Distance",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter(),
            unit: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
    )
    
    fileprivate static let crossTrainerDistance = Self(
        codings: [
            Coding(
                code: HKMetadataKeyCrossTrainerDistance.asFHIRStringPrimitive(),
                display: "Cross Trainer Distance",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .meter(),
            unit: "m",
            system: .unitsOfMeasureSystem,
            code: "m"
        )
    )
    
    fileprivate static let highHeartRateEventThreshold = Self(
        codings: [
            Coding(
                code: HKMetadataKeyHeartRateEventThreshold.asFHIRStringPrimitive(),
                display: "Heart Rate Event Threshold",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            ),
            Coding(
                code: "8867-4",
                display: "Heart rate",
                system: .loincSystem
            ),
            Coding(
                code: "364075005",
                display: "Heart rate",
                system: .snomedCT
            )
        ],
        unit: Unit(
            hkUnit: .count().unitDivided(by: .minute()),
            unit: "beats/min",
            system: .unitsOfMeasureSystem,
            code: "/min"
        )
    )
    
    fileprivate static let averageMETs = Self(
        codings: [
            Coding(
                code: HKMetadataKeyAverageMETs.asFHIRStringPrimitive(),
                display: "Average METs",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .largeCalorie().unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .hour())),
            unit: "kcal/(kg*hr)",
            system: .unitsOfMeasureSystem,
            code: "kcal/(kg.h)"
        )
    )
    
    fileprivate static let audioExposureLevel = Self(
        codings: [
            Coding(
                code: HKMetadataKeyAudioExposureLevel.asFHIRStringPrimitive(),
                display: "Audio Exposure Level",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .init(from: "dBASPL"),
            unit: "dB(SPL)",
            system: .unitsOfMeasureSystem,
            code: "dB[SPL]"
        )
    )
    
    fileprivate static let audioExposureDuration = Self(
        codings: [
            Coding(
                code: HKMetadataKeyAudioExposureDuration.asFHIRStringPrimitive(),
                display: "Audio Exposure Duration",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .second(),
            unit: "s",
            system: .unitsOfMeasureSystem,
            code: "s"
        )
    )
    
    fileprivate static let barometricPressure = Self(
        codings: [
            Coding(
                code: HKMetadataKeyBarometricPressure.asFHIRStringPrimitive(),
                display: "Barometric Pressure",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .millimeterOfMercury(),
            unit: "mmHg",
            system: .unitsOfMeasureSystem,
            code: "mm[Hg]"
        )
    )
    
    fileprivate static let vo2MaxValue = Self(
        codings: [
            Coding(
                code: HKMetadataKeyVO2MaxValue.asFHIRStringPrimitive(),
                display: "VO2Max Value",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .init(from: "mL/kg*min"),
            unit: "mL/kg/min",
            system: .unitsOfMeasureSystem,
            code: "mL/kg/min"
        )
    )
    
    fileprivate static let lowCardioFitnessEventThreshold = Self(
        codings: [
            Coding(
                code: HKMetadataKeyLowCardioFitnessEventThreshold.asFHIRStringPrimitive(),
                display: "Low Cardio Fitness Event Threshold",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .init(from: "mL/kg*min"),
            unit: "mL/kg/min",
            system: .unitsOfMeasureSystem,
            code: "mL/kg/min"
        )
    )
    
    fileprivate static let headphoneGain = Self(
        codings: [
            Coding(
                code: HKMetadataKeyHeadphoneGain.asFHIRStringPrimitive(),
                display: "Headphone Gain",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .decibelAWeightedSoundPressureLevel(),
            unit: "dB(SPL)",
            system: .unitsOfMeasureSystem,
            code: "dB[SPL]"
        )
    )
    
    fileprivate static let maximumLightIntensity = Self(
        codings: [
            Coding(
                code: HKMetadataKeyMaximumLightIntensity.asFHIRStringPrimitive(),
                display: "Maximum Light Intensity",
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        ],
        unit: Unit(
            hkUnit: .lux(),
            unit: "lux",
            system: .unitsOfMeasureSystem,
            code: "lx"
        )
    )
}

#endif
