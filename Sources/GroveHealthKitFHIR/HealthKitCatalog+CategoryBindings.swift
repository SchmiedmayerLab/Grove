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
extension HealthKitCatalog {
    // A closed source-type dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func categoryBinding(for identifier: String) -> HealthKitFHIRBinding? {
        // Added in the iOS 26 SDK after this exhaustive enum was introduced. Compare the
        // frozen catalog identifier so the adapter still builds at its iOS 18 deployment
        // floor while treating the event only as the source notification occurrence.
        if identifier == "HKCategoryTypeIdentifierHypertensionEvent" {
            return .notification(HealthKitMeasurementCatalog.hypertensionNotification)
        }
        switch HKCategoryTypeIdentifier(rawValue: identifier) {
        case .abdominalCramps:
            return .severity(HealthKitMeasurementCatalog.symptomAbdominalCramps)
        case .acne:
            return .severity(HealthKitMeasurementCatalog.symptomAcne)
        case .appetiteChanges:
            return .categoryValue(
                HealthKitMeasurementCatalog.symptomAppetiteChanges,
                absorption: .appetiteChanges
            )
        case .appleStandHour:
            return .categoryValue(HealthKitMeasurementCatalog.appleStandHour, absorption: .appleStandHour)
        case .bladderIncontinence:
            return .severity(HealthKitMeasurementCatalog.bladderIncontinence)
        case .bleedingAfterPregnancy:
            return .categoryValue(
                HealthKitMeasurementCatalog.bleedingAfterPregnancy,
                absorption: .vaginalBleeding
            )
        case .bleedingDuringPregnancy:
            return .categoryValue(
                HealthKitMeasurementCatalog.bleedingDuringPregnancy,
                absorption: .vaginalBleeding
            )
        case .bloating:
            return .severity(HealthKitMeasurementCatalog.symptomBloating)
        case .breastPain:
            return .severity(HealthKitMeasurementCatalog.symptomBreastPain)
        case .cervicalMucusQuality:
            return .categoryValue(MeasurementCatalog.cervicalMucusQuality, absorption: .cervicalMucusQuality)
        case .chestTightnessOrPain:
            return .severity(HealthKitMeasurementCatalog.symptomChestTightnessOrPain)
        case .chills:
            return .severity(HealthKitMeasurementCatalog.symptomChills)
        case .constipation:
            return .severity(HealthKitMeasurementCatalog.symptomConstipation)
        case .contraceptive:
            return .categoryValue(HealthKitMeasurementCatalog.contraceptiveUse, absorption: .contraceptive)
        case .coughing:
            return .severity(HealthKitMeasurementCatalog.symptomCoughing)
        case .diarrhea:
            return .severity(HealthKitMeasurementCatalog.symptomDiarrhea)
        case .dizziness:
            return .severity(HealthKitMeasurementCatalog.symptomDizziness)
        case .drySkin:
            return .severity(HealthKitMeasurementCatalog.symptomDrySkin)
        case .fainting:
            return .severity(HealthKitMeasurementCatalog.symptomFainting)
        case .fatigue:
            return .severity(HealthKitMeasurementCatalog.symptomFatigue)
        case .fever:
            return .severity(HealthKitMeasurementCatalog.symptomFever)
        case .generalizedBodyAche:
            return .severity(HealthKitMeasurementCatalog.symptomGeneralizedBodyAche)
        case .hairLoss:
            return .severity(HealthKitMeasurementCatalog.symptomHairLoss)
        case .handwashingEvent:
            return .sessionDuration(HealthKitMeasurementCatalog.handwashingSession)
        case .headache:
            return .severity(HealthKitMeasurementCatalog.symptomHeadache)
        case .heartburn:
            return .severity(HealthKitMeasurementCatalog.symptomHeartburn)
        case .hotFlashes:
            return .severity(HealthKitMeasurementCatalog.symptomHotFlashes)
        case .intermenstrualBleeding:
            return .fixedCode(MeasurementCatalog.intermenstrualBleeding)
        case .lactation:
            return .fixedCode(HealthKitMeasurementCatalog.lactationStatus)
        case .lossOfSmell:
            return .severity(HealthKitMeasurementCatalog.symptomLossOfSmell)
        case .lossOfTaste:
            return .severity(HealthKitMeasurementCatalog.symptomLossOfTaste)
        case .lowerBackPain:
            return .severity(HealthKitMeasurementCatalog.symptomLowerBackPain)
        case .memoryLapse:
            return .severity(HealthKitMeasurementCatalog.symptomMemoryLapse)
        case .menstrualFlow:
            return .categoryValue(MeasurementCatalog.menstruationFlow, absorption: .vaginalBleeding)
        case .mindfulSession:
            return .sessionDuration(MeasurementCatalog.mindfulnessSession)
        case .moodChanges:
            return .presence(HealthKitMeasurementCatalog.symptomMoodChanges)
        case .nausea:
            return .severity(HealthKitMeasurementCatalog.symptomNausea)
        case .nightSweats:
            return .severity(HealthKitMeasurementCatalog.symptomNightSweats)
        case .ovulationTestResult:
            return .categoryValue(MeasurementCatalog.ovulationTestResult, absorption: .ovulationTestResult)
        case .pelvicPain:
            return .severity(HealthKitMeasurementCatalog.symptomPelvicPain)
        case .pregnancy:
            return .fixedCode(HealthKitMeasurementCatalog.pregnancyStatus)
        case .pregnancyTestResult:
            return .categoryValue(
                HealthKitMeasurementCatalog.pregnancyTestResult,
                absorption: .pregnancyTestResult
            )
        case .progesteroneTestResult:
            return .categoryValue(
                HealthKitMeasurementCatalog.progesteroneTestResult,
                absorption: .progesteroneTestResult
            )
        case .rapidPoundingOrFlutteringHeartbeat:
            return .severity(HealthKitMeasurementCatalog.symptomRapidPoundingOrFlutteringHeartbeat)
        case .runnyNose:
            return .severity(HealthKitMeasurementCatalog.symptomRunnyNose)
        case .sexualActivity:
            return .sexualActivity
        case .shortnessOfBreath:
            return .severity(HealthKitMeasurementCatalog.symptomShortnessOfBreath)
        case .sinusCongestion:
            return .severity(HealthKitMeasurementCatalog.symptomSinusCongestion)
        case .skippedHeartbeat:
            return .severity(HealthKitMeasurementCatalog.symptomSkippedHeartbeat)
        case .sleepAnalysis:
            return .sleepStage
        case .sleepChanges:
            return .presence(HealthKitMeasurementCatalog.symptomSleepChanges)
        case .soreThroat:
            return .severity(HealthKitMeasurementCatalog.symptomSoreThroat)
        case .toothbrushingEvent:
            return .sessionDuration(HealthKitMeasurementCatalog.toothbrushingSession)
        case .vaginalDryness:
            return .severity(HealthKitMeasurementCatalog.vaginalDryness)
        case .vomiting:
            return .severity(HealthKitMeasurementCatalog.symptomVomiting)
        case .wheezing:
            return .severity(HealthKitMeasurementCatalog.symptomWheezing)
        case .highHeartRateEvent:
            return .notification(HealthKitMeasurementCatalog.highHeartRateNotification)
        case .lowHeartRateEvent:
            return .notification(HealthKitMeasurementCatalog.lowHeartRateNotification)
        case .irregularHeartRhythmEvent:
            return .notification(HealthKitMeasurementCatalog.irregularHeartRhythmNotification)
        case .sleepApneaEvent:
            return .notification(HealthKitMeasurementCatalog.sleepApneaNotification)
        case .lowCardioFitnessEvent:
            return .notification(
                HealthKitMeasurementCatalog.lowCardioFitnessNotification,
                values: [HKCategoryValueLowCardioFitnessEvent.lowFitness.rawValue: "low-fitness"]
            )
        case .appleWalkingSteadinessEvent:
            return .notification(
                HealthKitMeasurementCatalog.walkingSteadinessNotification,
                values: [
                    HKCategoryValueAppleWalkingSteadinessEvent.initialLow.rawValue: "initial-low",
                    HKCategoryValueAppleWalkingSteadinessEvent.initialVeryLow.rawValue: "initial-very-low",
                    HKCategoryValueAppleWalkingSteadinessEvent.repeatLow.rawValue: "repeat-low",
                    HKCategoryValueAppleWalkingSteadinessEvent.repeatVeryLow.rawValue: "repeat-very-low"
                ]
            )
        case .environmentalAudioExposureEvent:
            return .notification(
                HealthKitMeasurementCatalog.environmentalAudioExposureNotification,
                values: [HKCategoryValueEnvironmentalAudioExposureEvent.momentaryLimit.rawValue: "momentary-limit"]
            )
        case .headphoneAudioExposureEvent:
            return .notification(
                HealthKitMeasurementCatalog.headphoneAudioExposureNotification,
                values: [HKCategoryValueHeadphoneAudioExposureEvent.sevenDayLimit.rawValue: "seven-day-limit"]
            )
        case .irregularMenstrualCycles:
            return .notification(HealthKitMeasurementCatalog.irregularMenstrualCycles)
        case .infrequentMenstrualCycles:
            return .notification(HealthKitMeasurementCatalog.infrequentMenstrualCycles)
        case .prolongedMenstrualPeriods:
            return .notification(HealthKitMeasurementCatalog.prolongedMenstrualPeriods)
        case .persistentIntermenstrualBleeding:
            return .notification(HealthKitMeasurementCatalog.persistentIntermenstrualBleeding)
        default:
            return nil
        }
    }
}

#endif
