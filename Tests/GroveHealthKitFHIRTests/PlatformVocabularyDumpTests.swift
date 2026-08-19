//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


private struct VocabularyDump: Encodable {
    struct Concept: Encodable {
        let code: String
        let display: String
    }

    struct CodeSystem: Encodable {
        let system: String
        let title: String
        let type: String
        let concepts: [Concept]
    }

    let codeSystems: [CodeSystem]
    let metadataKeys: [String]
}


/// Dumps the platform vocabulary the framework writes, for the implementation guide to publish.
///
/// `tools/generate-platform-vocabulary.py` in the grove-fhir workspace used to re-derive
/// the code system names, codes and displays from the macro invocations with a word
/// splitter of its own, and the two spellings drifted. It now reads this dump, so the
/// values the framework writes are the only ones there are.
///
/// Run with `GROVE_VOCABULARY_DUMP` set to the destination path to write it.
@Suite
struct PlatformVocabularyDumpTests {
    /// Every type Grove codes through `@SynthesizeDisplayProperty`.
    static var codedTypes: [any FHIRCodingConvertible.Type] {
        [
            HKAppleECGAlgorithmVersion.self,
            HKAppleWalkingSteadinessClassification.self,
            HKBloodGlucoseMealTime.self,
            HKBodyTemperatureSensorLocation.self,
            HKCategoryValueAppetiteChanges.self,
            HKCategoryValueAppleStandHour.self,
            HKCategoryValueAppleWalkingSteadinessEvent.self,
            HKCategoryValueCervicalMucusQuality.self,
            HKCategoryValueContraceptive.self,
            HKCategoryValueEnvironmentalAudioExposureEvent.self,
            HKCategoryValueHeadphoneAudioExposureEvent.self,
            HKCategoryValueLowCardioFitnessEvent.self,
            HKCategoryValueMenstrualFlow.self,
            HKCategoryValueOvulationTestResult.self,
            HKCategoryValuePregnancyTestResult.self,
            HKCategoryValuePresence.self,
            HKCategoryValueProgesteroneTestResult.self,
            HKCategoryValueSeverity.self,
            HKCategoryValueSleepAnalysis.self,
            HKCategoryValueVaginalBleeding.self,
            HKCyclingFunctionalThresholdPowerTestType.self,
            HKDevicePlacementSide.self,
            HKElectrocardiogram.Classification.self,
            HKElectrocardiogram.SymptomsStatus.self,
            HKHeartRateMotionContext.self,
            HKHeartRateRecoveryTestType.self,
            HKHeartRateSensorLocation.self,
            HKInsulinDeliveryReason.self,
            HKPhysicalEffortEstimationType.self,
            HKStateOfMind.Association.self,
            HKStateOfMind.Kind.self,
            HKStateOfMind.Label.self,
            HKStateOfMind.ValenceClassification.self,
            HKSwimmingStrokeStyle.self,
            HKUserMotionContext.self,
            HKVO2MaxTestType.self,
            HKWaterSalinity.self,
            HKWeatherCondition.self,
            HKWorkoutSwimmingLocationType.self
        ]
    }

    /// Where the dump lands: the repository's build directory, derived from this file's
    /// own path. `xcodebuild` does not forward the shell's environment into the test
    /// process, so the destination cannot come from a variable.
    static var dumpURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GroveHealthKitFHIRTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent(".build/grove-vocabulary.json")
    }

    @Test
    func everyTypeGetsItsOwnCodeSystem() {
        let systems = Self.codedTypes.map { $0.fhirSystemName }
        #expect(Set(systems).count == systems.count, "two types would publish the same code system URL")
        for system in systems {
            #expect(system.hasPrefix("healthkit-"), "\(system) is not a HealthKit system name")
        }
    }

    @Test
    func writeVocabularyDump() throws {
        let destination = Self.dumpURL
        let dump = VocabularyDump(
            codeSystems: Self.codedTypes.map { type in
                VocabularyDump.CodeSystem(
                    system: type.fhirSystemName,
                    title: type.fhirSystemTitle,
                    type: type.fhirPlatformTypeName,
                    concepts: type.fhirPublishedCodes.map { VocabularyDump.Concept(code: $0.code, display: $0.display) }
                )
            },
            metadataKeys: MetadataKeyVocabularyTests.publishedKeys.map(\.code).sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(dump).write(to: destination)
    }
}

#endif
