//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRCatalog {
    // A closed source-type dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func categoryBinding(for identifier: String) -> HealthKitFHIRBinding? {
        switch HKCategoryTypeIdentifier(rawValue: identifier) {
        case .abdominalCramps:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomAbdominalCramps)
        case .acne:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomAcne)
        case .appetiteChanges:
            return .categoryValue(
                GroveFHIRHealthKitMeasurementCatalog.symptomAppetiteChanges,
                absorption: .appetiteChanges
            )
        case .appleStandHour:
            return .categoryValue(GroveFHIRHealthKitMeasurementCatalog.appleStandHour, absorption: .appleStandHour)
        case .bladderIncontinence:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.bladderIncontinence)
        case .bleedingAfterPregnancy:
            return .categoryValue(
                GroveFHIRHealthKitMeasurementCatalog.bleedingAfterPregnancy,
                absorption: .vaginalBleeding
            )
        case .bleedingDuringPregnancy:
            return .categoryValue(
                GroveFHIRHealthKitMeasurementCatalog.bleedingDuringPregnancy,
                absorption: .vaginalBleeding
            )
        case .bloating:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomBloating)
        case .breastPain:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomBreastPain)
        case .cervicalMucusQuality:
            return .categoryValue(GroveFHIRMeasurementCatalog.cervicalMucusQuality, absorption: .cervicalMucusQuality)
        case .chestTightnessOrPain:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomChestTightnessOrPain)
        case .chills:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomChills)
        case .constipation:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomConstipation)
        case .contraceptive:
            return .categoryValue(GroveFHIRHealthKitMeasurementCatalog.contraceptiveUse, absorption: .contraceptive)
        case .coughing:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomCoughing)
        case .diarrhea:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomDiarrhea)
        case .dizziness:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomDizziness)
        case .drySkin:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomDrySkin)
        case .fainting:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomFainting)
        case .fatigue:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomFatigue)
        case .fever:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomFever)
        case .generalizedBodyAche:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomGeneralizedBodyAche)
        case .hairLoss:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomHairLoss)
        case .handwashingEvent:
            return .sessionDuration(GroveFHIRHealthKitMeasurementCatalog.handwashingSession)
        case .headache:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomHeadache)
        case .heartburn:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomHeartburn)
        case .hotFlashes:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomHotFlashes)
        case .intermenstrualBleeding:
            return .fixedCode(GroveFHIRMeasurementCatalog.intermenstrualBleeding)
        case .lactation:
            return .fixedCode(GroveFHIRHealthKitMeasurementCatalog.lactationStatus)
        case .lossOfSmell:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomLossOfSmell)
        case .lossOfTaste:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomLossOfTaste)
        case .lowerBackPain:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomLowerBackPain)
        case .memoryLapse:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomMemoryLapse)
        case .menstrualFlow:
            return .categoryValue(GroveFHIRMeasurementCatalog.menstruationFlow, absorption: .vaginalBleeding)
        case .mindfulSession:
            return .sessionDuration(GroveFHIRMeasurementCatalog.mindfulnessSession)
        case .moodChanges:
            return .presence(GroveFHIRHealthKitMeasurementCatalog.symptomMoodChanges)
        case .nausea:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomNausea)
        case .nightSweats:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomNightSweats)
        case .ovulationTestResult:
            return .categoryValue(GroveFHIRMeasurementCatalog.ovulationTestResult, absorption: .ovulationTestResult)
        case .pelvicPain:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomPelvicPain)
        case .pregnancy:
            return .fixedCode(GroveFHIRHealthKitMeasurementCatalog.pregnancyStatus)
        case .pregnancyTestResult:
            return .categoryValue(
                GroveFHIRHealthKitMeasurementCatalog.pregnancyTestResult,
                absorption: .pregnancyTestResult
            )
        case .progesteroneTestResult:
            return .categoryValue(
                GroveFHIRHealthKitMeasurementCatalog.progesteroneTestResult,
                absorption: .progesteroneTestResult
            )
        case .rapidPoundingOrFlutteringHeartbeat:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomRapidPoundingOrFlutteringHeartbeat)
        case .runnyNose:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomRunnyNose)
        case .sexualActivity:
            return .sexualActivity
        case .shortnessOfBreath:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomShortnessOfBreath)
        case .sinusCongestion:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomSinusCongestion)
        case .skippedHeartbeat:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomSkippedHeartbeat)
        case .sleepAnalysis:
            return .sleepStage
        case .sleepChanges:
            return .presence(GroveFHIRHealthKitMeasurementCatalog.symptomSleepChanges)
        case .soreThroat:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomSoreThroat)
        case .toothbrushingEvent:
            return .sessionDuration(GroveFHIRHealthKitMeasurementCatalog.toothbrushingSession)
        case .vaginalDryness:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.vaginalDryness)
        case .vomiting:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomVomiting)
        case .wheezing:
            return .severity(GroveFHIRHealthKitMeasurementCatalog.symptomWheezing)
        default:
            return nil
        }
    }
}

#endif
