//
// This source file is part of the HealthKitOnFHIR open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import HealthKitOnFHIRMacros
import ModelsR4


/// Models a value type used by a `HKCategoryType`.
protocol FHIRCodingConvertible {
    static var system: FHIRPrimitive<FHIRURI> { get }

    var code: String { get }
    var display: String? { get }

    init?(rawValue: Int)
}

protocol FHIRCodingConvertibleHKEnum: FHIRCodingConvertible {}

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


extension FHIRCodingConvertibleHKEnum {
    static var system: FHIRPrimitive<FHIRURI> {
        let typename = String(describing: Self.self).lowercased()
        return "https://developer.apple.com/documentation/healthkit/\(typename)".asFHIRURIPrimitive()! // swiftlint:disable:this force_unwrapping
    }
}


// MARK: Extensions

@available(iOS 18.0, macOS 15.0, watchOS 11.0, *)
@SynthesizeDisplayProperty(
    HKCategoryValueVaginalBleeding.self,
    .unspecified, .light, .medium, .heavy, .none
)
extension HKCategoryValueVaginalBleeding: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueCervicalMucusQuality.self,
    .dry, .sticky, .creamy, .watery, .eggWhite
)
extension HKCategoryValueCervicalMucusQuality: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueMenstrualFlow.self,
    .unspecified, .light, .medium, .heavy, .none
)
extension HKCategoryValueMenstrualFlow: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueOvulationTestResult.self,
    .negative, .luteinizingHormoneSurge, .indeterminate, .estrogenSurge
)
extension HKCategoryValueOvulationTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueContraceptive.self,
    .unspecified, .implant, .injection, .intrauterineDevice, .intravaginalRing, .oral, .patch
)
extension HKCategoryValueContraceptive: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueSleepAnalysis.self,
    .inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM
)
extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppetiteChanges.self,
    .unspecified, .noChange, .decreased, .increased
)
extension HKCategoryValueAppetiteChanges: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueEnvironmentalAudioExposureEvent.self,
    .momentaryLimit
)
extension HKCategoryValueEnvironmentalAudioExposureEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueHeadphoneAudioExposureEvent.self,
    .sevenDayLimit
)
extension HKCategoryValueHeadphoneAudioExposureEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueLowCardioFitnessEvent.self,
    .lowFitness
)
extension HKCategoryValueLowCardioFitnessEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKAppleWalkingSteadinessClassification.self,
    .ok, .low, .veryLow
)
extension HKAppleWalkingSteadinessClassification: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppleWalkingSteadinessEvent.self,
    .initialLow, .initialVeryLow, .repeatLow, .repeatVeryLow
)
extension HKCategoryValueAppleWalkingSteadinessEvent: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValuePregnancyTestResult.self,
    .negative, .positive, .indeterminate
)
extension HKCategoryValuePregnancyTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueProgesteroneTestResult.self,
    .negative, .positive, .indeterminate
)
extension HKCategoryValueProgesteroneTestResult: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueAppleStandHour.self,
    .stood, .idle
)
extension HKCategoryValueAppleStandHour: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValueSeverity.self,
    .unspecified, .notPresent, .mild, .moderate, .severe
)
extension HKCategoryValueSeverity: FHIRCodingConvertibleHKEnum {}

@available(iOS 18, macOS 15, watchOS 11, *)
@SynthesizeDisplayProperty(
    HKCategoryValuePresence.self,
    .present, .notPresent
)
extension HKCategoryValuePresence: FHIRCodingConvertibleHKEnum {}
