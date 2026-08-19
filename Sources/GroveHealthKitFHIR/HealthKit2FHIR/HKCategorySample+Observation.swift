//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveHealthKit
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategorySample: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        guard let sampleType = SampleType(self.categoryType),
              let categoryMapping = mapping.categoryTypesMapping[sampleType] else {
            throw GroveHealthKitFHIRError.notSupported
        }
        observation.append(codings: categoryMapping.codings)
        observation.append(categories: categoryMapping.categories.map { CodeableConcept(coding: [$0]) })
        let assocDataInfo = try categoryType.associatedDataInfo
        if let valueType = assocDataInfo.valueType {
            guard let value = valueType.init(rawValue: self.value) else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            observation.value = .codeableConcept(CodeableConcept(coding: [value.asCoding] + value.additionalCodings))
        }
        // A category type without a value type carries no value: repeating the identifier `code` already
        // states would observe nothing, the event itself being asserted by `effective[x]`.
        // Sorted, so the same sample always yields the same component order.
        for (_, component) in try metadataComponents(mapping: mapping.quantityTypesMapping).sorted(by: { $0.key < $1.key }) {
            observation.append(component: component)
        }
    }

    /// The components promoted from this sample's metadata, keyed by the metadata entry each one consumed.
    ///
    /// Every component is coded by its platform metadata key, which is what lets the Layer-4 envelope skip
    /// exactly what Layer 3 took.
    func metadataComponents(mapping: QuantityTypesFHIRMapping) throws -> [String: ObservationComponent] {
        var components: [String: ObservationComponent] = [:]
        for metadataKey in try categoryType.associatedDataInfo.metadataKeys {
            guard let value = self.metadata?[metadataKey],
                  let keyCoding = HKCategoryType.coding(forMetadataKey: metadataKey) else {
                continue
            }
            if let quantity = value as? HKQuantity {
                guard let quantityType = HKCategoryType.quantityType(forMetadataKey: metadataKey),
                      let quantityMapping = mapping[quantityType] else {
                    continue
                }
                // A threshold is an alert setting, not a reading: coding it as the concept it triggers on
                // would let a query for that concept ingest configuration as measurement.
                let measurementCodings = HKCategoryType.isEventThreshold(metadataKey) ? [] : quantityMapping.codings
                components[metadataKey] = ObservationComponent(
                    code: CodeableConcept(coding: [keyCoding] + measurementCodings),
                    value: .quantity(try quantity.buildQuantity(mapping: quantityMapping))
                )
            } else if let flag = value as? Bool {
                components[metadataKey] = ObservationComponent(
                    code: CodeableConcept(coding: [keyCoding]),
                    value: .boolean(flag.asPrimitive())
                )
            }
        }
        return components
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryType {
    fileprivate static func coding(forMetadataKey key: String) -> Coding? {
        let display: String? = switch key {
        case HKMetadataKeyMenstrualCycleStart: "Menstrual Cycle Start"
        case HKMetadataKeySexualActivityProtectionUsed: "Sexual Activity: Protection Used"
        case HKMetadataKeyHeartRateEventThreshold: "Heart Rate Event Threshold"
        case HKMetadataKeyLowCardioFitnessEventThreshold: "Low Cardio Fitness Event Threshold"
        case HKMetadataKeyVO2MaxValue: "VO2 Max Value"
        default: nil
        }
        return display.map { display in
            Coding(
                code: key.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.healthKitMetadataKey
            )
        }
    }

    fileprivate static func isEventThreshold(_ key: String) -> Bool {
        key == HKMetadataKeyHeartRateEventThreshold || key == HKMetadataKeyLowCardioFitnessEventThreshold
    }

    fileprivate static func quantityType(forMetadataKey key: String) -> SampleType<HKQuantitySample>? {
        switch key {
        case HKMetadataKeyHeartRateEventThreshold:
            .heartRate
        case HKMetadataKeyLowCardioFitnessEventThreshold, HKMetadataKeyVO2MaxValue:
            .vo2Max
        default:
            nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryType {
    /// Information about the associated data carried by a sample of a specific category type.
    struct AssociatedDataInfo {
        static var noDataCarried: Self { .init(valueType: nil) }
        
        let valueType: (any FHIRCodingConvertibleHKEnum.Type)?
        let metadataKeys: Set<String>
        
        init(valueType: (any FHIRCodingConvertibleHKEnum.Type)?, metadataKeys: Set<String> = []) {
            self.valueType = valueType
            self.metadataKeys = metadataKeys
        }
    }
    
    /// The category type's associated (FHIR-compatible) Category Value Type.
    ///
    /// - throws: if the category type is unknown.
    var associatedDataInfo: AssociatedDataInfo {
        get throws {
            try HKCategoryTypeIdentifier(rawValue: self.identifier).associatedDataInfo
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryTypeIdentifier {
    /// The category type's associated (FHIR-compatible) Category Value Type.
    ///
    /// - throws: if the category type is unknown
    var associatedDataInfo: HKCategoryType.AssociatedDataInfo {
        get throws {
            switch self {
            case .appleStandHour:
                return .init(valueType: HKCategoryValueAppleStandHour.self)
            case .environmentalAudioExposureEvent:
                return .init(valueType: HKCategoryValueEnvironmentalAudioExposureEvent.self)
            case .headphoneAudioExposureEvent:
                return .init(valueType: HKCategoryValueHeadphoneAudioExposureEvent.self)
            case .highHeartRateEvent, .lowHeartRateEvent:
                return .init(
                    valueType: nil,
                    metadataKeys: [HKMetadataKeyHeartRateEventThreshold]
                )
            case .irregularHeartRhythmEvent:
                return .noDataCarried
            case .lowCardioFitnessEvent:
                return .init(
                    valueType: HKCategoryValueLowCardioFitnessEvent.self,
                    metadataKeys: [HKMetadataKeyVO2MaxValue, HKMetadataKeyLowCardioFitnessEventThreshold]
                )
            case .mindfulSession:
                return .noDataCarried
            case .appleWalkingSteadinessEvent:
                return .init(valueType: HKCategoryValueAppleWalkingSteadinessEvent.self)
            case .handwashingEvent, .toothbrushingEvent:
                return .noDataCarried
            case .cervicalMucusQuality:
                return .init(valueType: HKCategoryValueCervicalMucusQuality.self)
            case .contraceptive:
                return .init(valueType: HKCategoryValueContraceptive.self)
            case .infrequentMenstrualCycles, .intermenstrualBleeding, .irregularMenstrualCycles, .lactation, .persistentIntermenstrualBleeding:
                return .noDataCarried
            case .menstrualFlow:
                return .init(
                    valueType: HKCategoryValueMenstrualFlow.self,
                    metadataKeys: [HKMetadataKeyMenstrualCycleStart]
                )
            case .ovulationTestResult:
                return .init(valueType: HKCategoryValueOvulationTestResult.self)
            case .pregnancy:
                return .noDataCarried
            case .pregnancyTestResult:
                return .init(valueType: HKCategoryValuePregnancyTestResult.self)
            case .progesteroneTestResult:
                return .init(valueType: HKCategoryValueProgesteroneTestResult.self)
            case .prolongedMenstrualPeriods:
                return .noDataCarried
            case .sexualActivity:
                return .init(valueType: nil, metadataKeys: [HKMetadataKeySexualActivityProtectionUsed])
            case .sleepAnalysis:
                return .init(valueType: HKCategoryValueSleepAnalysis.self)
            case .abdominalCramps:
                return .init(valueType: HKCategoryValueSeverity.self)
            case .acne:
                return .init(valueType: HKCategoryValueSeverity.self)
            case .appetiteChanges:
                return .init(valueType: HKCategoryValueAppetiteChanges.self)
            case .bladderIncontinence, .bloating, .breastPain, .chestTightnessOrPain, .chills, .constipation,
                    .coughing, .diarrhea, .dizziness, .drySkin, .fainting, .fatigue, .fever, .generalizedBodyAche, .hairLoss,
                    .headache, .heartburn, .hotFlashes, .lossOfSmell, .lossOfTaste, .lowerBackPain, .memoryLapse, .nausea,
                    .nightSweats, .pelvicPain, .rapidPoundingOrFlutteringHeartbeat, .runnyNose, .shortnessOfBreath, .sinusCongestion,
                    .skippedHeartbeat, .soreThroat, .vaginalDryness, .vomiting, .wheezing:
                return .init(valueType: HKCategoryValueSeverity.self)
            case .moodChanges, .sleepChanges:
                return .init(valueType: HKCategoryValuePresence.self)
            default:
                // we need to put these in here, in the default, since we can't do the #available check as part of the switch cases above...
                if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *),
                   self == .bleedingDuringPregnancy || self == .bleedingAfterPregnancy {
                    return .init(valueType: HKCategoryValueVaginalBleeding.self)
                } else {
                    throw GroveHealthKitFHIRError.notSupported
                }
            }
        }
    }
}

#endif
