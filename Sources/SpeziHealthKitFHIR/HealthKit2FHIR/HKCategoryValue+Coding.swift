//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import ModelsR4
import SpeziHealthKitFHIRMacros


/// Models a value type used by a `HKCategoryType`.
protocol FHIRCodingConvertible {
    static var system: FHIRPrimitive<FHIRURI> { get }
    
    var code: String { get }
    var display: String? { get }
    
    init?(rawValue: Int)
}

extension FHIRCodingConvertible {
    var asCoding: Coding {
        Coding(
            code: code.asFHIRStringPrimitive(),
            display: display?.asFHIRStringPrimitive(),
            system: Self.system
        )
    }
}


extension FHIRCodingConvertible where Self: RawRepresentable, RawValue == Int {
    var code: String {
        String(rawValue)
    }
}


protocol FHIRCodingConvertibleHKEnum: FHIRCodingConvertible {}

extension FHIRCodingConvertibleHKEnum {
    static var system: FHIRPrimitive<FHIRURI> {
        let typename = String(describing: Self.self).lowercased()
        return "https://developer.apple.com/documentation/healthkit/\(typename)".asFHIRURIPrimitive()! // swiftlint:disable:this force_unwrapping
    }
}


// MARK: Extensions

@available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *)
@SynthesizeDisplayProperty(
    HKCategoryValueVaginalBleeding.self,
    .unspecified, .light, .medium, .heavy, .none
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueVaginalBleeding: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueCervicalMucusQuality.self,
    .dry, .sticky, .creamy, .watery, .eggWhite
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueCervicalMucusQuality: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueMenstrualFlow.self,
    .unspecified, .light, .medium, .heavy, .none
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueMenstrualFlow: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueOvulationTestResult.self,
    .negative, .luteinizingHormoneSurge, .indeterminate, .estrogenSurge
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueOvulationTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueContraceptive.self,
    .unspecified, .implant, .injection, .intrauterineDevice, .intravaginalRing, .oral, .patch
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueContraceptive: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueSleepAnalysis.self,
    .inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppetiteChanges.self,
    .unspecified, .noChange, .decreased, .increased
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueAppetiteChanges: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueEnvironmentalAudioExposureEvent.self,
    .momentaryLimit
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueEnvironmentalAudioExposureEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueHeadphoneAudioExposureEvent.self,
    .sevenDayLimit
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueHeadphoneAudioExposureEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueLowCardioFitnessEvent.self,
    .lowFitness
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueLowCardioFitnessEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKAppleWalkingSteadinessClassification.self,
    .ok, .low, .veryLow
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKAppleWalkingSteadinessClassification: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppleWalkingSteadinessEvent.self,
    .initialLow, .initialVeryLow, .repeatLow, .repeatVeryLow
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueAppleWalkingSteadinessEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValuePregnancyTestResult.self,
    .negative, .positive, .indeterminate
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValuePregnancyTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueProgesteroneTestResult.self,
    .negative, .positive, .indeterminate
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueProgesteroneTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppleStandHour.self,
    .stood, .idle
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueAppleStandHour: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueSeverity.self,
    .unspecified, .notPresent, .mild, .moderate, .severe
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueSeverity: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValuePresence.self,
    .present, .notPresent
)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValuePresence: FHIRCodingConvertibleHKEnum {}

#endif
