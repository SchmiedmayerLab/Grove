//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveHealthKitFHIRMacros
import HealthKit
import ModelsR4


/// Models a value type used by a `HKCategoryType`.
///
/// The coding members are synthesized by `@SynthesizeDisplayProperty`: `code` is the
/// Swift case name, and ``fhirSystemName`` names the Grove-published CodeSystem for
/// the type. Platform raw integers are deliberately not used as codes — Apple may
/// reassign them, and they carry no meaning to a consumer.
///
/// A value the platform reports but this build does not know is coded as
/// `unrecognized-platform-value`: several of these types declare an `unknown` case of
/// their own, so the fallback has to be a code Apple cannot also mean.
protocol FHIRCodingConvertible {
    /// The type's code system name within the Grove platform vocabulary,
    /// e.g. `healthkit-category-value-sleep-analysis`.
    static var fhirSystemName: String { get }
    /// The code system's title, e.g. `HealthKit Category Value Sleep Analysis`.
    static var fhirSystemTitle: String { get }
    /// The platform type the system publishes, spelled as the framework refers to it.
    static var fhirPlatformTypeName: String { get }
    /// Every code the mapping can write, including the `unrecognized-platform-value`
    /// sentinel — what the vocabulary generator publishes, so the code system stays
    /// complete without duplicating the case list.
    static var fhirPublishedCodes: [(code: String, display: String)] { get }

    var code: String { get }
    var display: String? { get }
    /// Parallel codings from standard vocabularies (e.g. LOINC sleep stages),
    /// appended after the HealthKit coding. A protocol requirement so conforming
    /// types' implementations dispatch dynamically.
    var additionalCodings: [Coding] { get }

    init?(rawValue: Int)
}

extension FHIRCodingConvertible {
    /// The type's canonical code system.
    static var system: FHIRPrimitive<FHIRURI> {
        FHIRPrimitive(FHIRURI(stringLiteral: "\(GroveFHIRVocabulary.platformCodeSystemBase)/\(fhirSystemName)"))
    }

    var asCoding: Coding {
        Coding(
            code: code.asFHIRStringPrimitive(),
            display: display?.asFHIRStringPrimitive(),
            system: Self.system
        )
    }

    /// Parallel codings from standard vocabularies (e.g. LOINC sleep stages),
    /// appended after the HealthKit coding.
    var additionalCodings: [Coding] { [] }
}


protocol FHIRCodingConvertibleHKEnum: FHIRCodingConvertible {}


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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryValueSleepAnalysis {
    /// LOINC sleep-stage codes carried alongside the HealthKit value, so consumers
    /// can aggregate stage durations without Apple-specific vocabulary.
    var additionalCodings: [Coding] {
        let loinc: (code: String, display: String)?
        switch self {
        case .inBed, .asleepUnspecified:
            loinc = ("93832-4", "Sleep duration")
        case .asleepREM:
            loinc = ("93829-0", "REM sleep duration")
        case .asleepCore:
            loinc = ("93830-8", "Light sleep duration")
        case .asleepDeep:
            loinc = ("93831-6", "Deep sleep duration")
        case .awake:
            loinc = nil
        @unknown default:
            loinc = nil
        }
        guard let loinc else {
            return []
        }
        return [
            Coding(
            code: loinc.code.asFHIRStringPrimitive(),
            display: loinc.display.asFHIRStringPrimitive(),
            system: .loincSystem
        )
        ]
    }
}
