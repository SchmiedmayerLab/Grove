//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(macOS) // macro tests can only be run on the host machine
import GroveHealthKitFHIRMacros
import GroveHealthKitFHIRMacrosImpl
import HealthKit
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

let testMacrosSpecs: [String: MacroSpec] = [
    "SynthesizeDisplayProperty": MacroSpec(type: SynthesizeDisplayPropertyMacro.self)
]

@Suite
struct GroveHealthKitFHIRMacrosTests {
    @Test
    func macro0() {
        assertMacroExpansion(
            """
            @SynthesizeDisplayProperty(
                HKCategoryValueSleepAnalysis.self,
                .inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM
            )
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {}
            """,
            expandedSource:
            """
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {

                var display: String? {
                    switch self {
                    case .inBed:
                        "in bed"
                    case .asleepUnspecified:
                        "asleep unspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleep core"
                    case .asleepDeep:
                        "asleep deep"
                    case .asleepREM:
                        "asleep REM"
                    @unknown default:
                        "unrecognized platform value"
                    }
                }

                var code: String {
                    switch self {
                    case .inBed:
                        "inBed"
                    case .asleepUnspecified:
                        "asleepUnspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleepCore"
                    case .asleepDeep:
                        "asleepDeep"
                    case .asleepREM:
                        "asleepREM"
                    @unknown default:
                        "unrecognized-platform-value"
                    }
                }

                static var fhirSystemName: String {
                    "healthkit-category-value-sleep-analysis"
                }

                static var fhirSystemTitle: String {
                    "HealthKit Category Value Sleep Analysis"
                }

                static var fhirPlatformTypeName: String {
                    "HKCategoryValueSleepAnalysis"
                }

                static var fhirPublishedCodes: [(code: String, display: String)] {
                    [("inBed", "in bed"), ("asleepUnspecified", "asleep unspecified"), ("awake", "awake"), ("asleepCore", "asleep core"), ("asleepDeep", "asleep deep"), ("asleepREM", "asleep REM"), ("unrecognized-platform-value", "unrecognized platform value")]
                }
            }
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
    
    @Test
    func macro1() {
        assertMacroExpansion(
            """
            @SynthesizeDisplayProperty(
                HKCategoryValueSleepAnalysis.self,
                .inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM
            )
            @available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *)
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {}
            """,
            expandedSource:
            """
            @available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *)
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {
            
                var display: String? {
                    switch self {
                    case .inBed:
                        "in bed"
                    case .asleepUnspecified:
                        "asleep unspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleep core"
                    case .asleepDeep:
                        "asleep deep"
                    case .asleepREM:
                        "asleep REM"
                    @unknown default:
                        "unrecognized platform value"
                    }
                }

                var code: String {
                    switch self {
                    case .inBed:
                        "inBed"
                    case .asleepUnspecified:
                        "asleepUnspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleepCore"
                    case .asleepDeep:
                        "asleepDeep"
                    case .asleepREM:
                        "asleepREM"
                    @unknown default:
                        "unrecognized-platform-value"
                    }
                }

                static var fhirSystemName: String {
                    "healthkit-category-value-sleep-analysis"
                }

                static var fhirSystemTitle: String {
                    "HealthKit Category Value Sleep Analysis"
                }

                static var fhirPlatformTypeName: String {
                    "HKCategoryValueSleepAnalysis"
                }

                static var fhirPublishedCodes: [(code: String, display: String)] {
                    [("inBed", "in bed"), ("asleepUnspecified", "asleep unspecified"), ("awake", "awake"), ("asleepCore", "asleep core"), ("asleepDeep", "asleep deep"), ("asleepREM", "asleep REM"), ("unrecognized-platform-value", "unrecognized platform value")]
                }
            }
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
    
    @Test
    func macro2() {
        assertMacroExpansion(
            """
            @SynthesizeDisplayProperty(
                HKCategoryValueSleepAnalysis.self,
                .inBed, .asleepUnspecified, .awake, .asleepCore,
                additionalCases: "asleepDeep", "asleepREM"
            )
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {}
            """,
            expandedSource:
            """
            extension HKCategoryValueSleepAnalysis: FHIRCodingConvertibleHKEnum {
            
                var display: String? {
                    switch self {
                    case .inBed:
                        "in bed"
                    case .asleepUnspecified:
                        "asleep unspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleep core"
                    case .asleepDeep:
                        "asleep deep"
                    case .asleepREM:
                        "asleep REM"
                    @unknown default:
                        "unrecognized platform value"
                    }
                }

                var code: String {
                    switch self {
                    case .inBed:
                        "inBed"
                    case .asleepUnspecified:
                        "asleepUnspecified"
                    case .awake:
                        "awake"
                    case .asleepCore:
                        "asleepCore"
                    case .asleepDeep:
                        "asleepDeep"
                    case .asleepREM:
                        "asleepREM"
                    @unknown default:
                        "unrecognized-platform-value"
                    }
                }

                static var fhirSystemName: String {
                    "healthkit-category-value-sleep-analysis"
                }

                static var fhirSystemTitle: String {
                    "HealthKit Category Value Sleep Analysis"
                }

                static var fhirPlatformTypeName: String {
                    "HKCategoryValueSleepAnalysis"
                }

                static var fhirPublishedCodes: [(code: String, display: String)] {
                    [("inBed", "in bed"), ("asleepUnspecified", "asleep unspecified"), ("awake", "awake"), ("asleepCore", "asleep core"), ("asleepDeep", "asleep deep"), ("asleepREM", "asleep REM"), ("unrecognized-platform-value", "unrecognized platform value")]
                }
            }
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    /// Acronyms and digits are where a hand-rolled splitter goes wrong, and the system
    /// name is a published URL, so both spellings are pinned here.
    @Test
    func acronymAndDigitSplitting() {
        assertMacroExpansion(
            """
            @SynthesizeDisplayProperty(
                HKVO2MaxTestType.self,
                .maxExercise60Minute
            )
            extension HKVO2MaxTestType: FHIRCodingConvertibleHKEnum {}
            """,
            expandedSource:
            """
            extension HKVO2MaxTestType: FHIRCodingConvertibleHKEnum {

                var display: String? {
                    switch self {
                    case .maxExercise60Minute:
                        "max exercise60 minute"
                    @unknown default:
                        "unrecognized platform value"
                    }
                }

                var code: String {
                    switch self {
                    case .maxExercise60Minute:
                        "maxExercise60Minute"
                    @unknown default:
                        "unrecognized-platform-value"
                    }
                }

                static var fhirSystemName: String {
                    "healthkit-vo2-max-test-type"
                }

                static var fhirSystemTitle: String {
                    "HealthKit VO2 Max Test Type"
                }

                static var fhirPlatformTypeName: String {
                    "HKVO2MaxTestType"
                }

                static var fhirPublishedCodes: [(code: String, display: String)] {
                    [("maxExercise60Minute", "max exercise60 minute"), ("unrecognized-platform-value", "unrecognized platform value")]
                }
            }
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
        assertMacroExpansion(
            """
            @SynthesizeDisplayProperty(
                HKAppleECGAlgorithmVersion.self,
                .version1
            )
            extension HKAppleECGAlgorithmVersion: FHIRCodingConvertibleHKEnum {}
            """,
            expandedSource:
            """
            extension HKAppleECGAlgorithmVersion: FHIRCodingConvertibleHKEnum {

                var display: String? {
                    switch self {
                    case .version1:
                        "version1"
                    @unknown default:
                        "unrecognized platform value"
                    }
                }

                var code: String {
                    switch self {
                    case .version1:
                        "version1"
                    @unknown default:
                        "unrecognized-platform-value"
                    }
                }

                static var fhirSystemName: String {
                    "healthkit-apple-ecg-algorithm-version"
                }

                static var fhirSystemTitle: String {
                    "HealthKit Apple ECG Algorithm Version"
                }

                static var fhirPlatformTypeName: String {
                    "HKAppleECGAlgorithmVersion"
                }

                static var fhirPublishedCodes: [(code: String, display: String)] {
                    [("version1", "version1"), ("unrecognized-platform-value", "unrecognized platform value")]
                }
            }
            """,
            macroSpecs: testMacrosSpecs,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
}
#endif
