//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire


/// How the participant feels on the day of the check-in.
enum EnergyLevel: String, QuestionnaireOption {
    case low
    case fair
    case good
    case great

    static let system = URL(string: "https://grovealliance.org/samples/CodeSystem/EnergyLevel")

    var title: String {
        switch self {
        case .low: "Low"
        case .fair: "Fair"
        case .good: "Good"
        case .great: "Great"
        }
    }
}


/// What the participant noticed over the past week.
enum HeartSymptom: String, QuestionnaireOption {
    case chestDiscomfort = "chest-discomfort"
    case shortnessOfBreath = "shortness-of-breath"
    case swollenAnkles = "swollen-ankles"
    case dizziness

    static let system = URL(string: "https://grovealliance.org/samples/CodeSystem/HeartSymptom")

    var title: String {
        switch self {
        case .chestDiscomfort: "Chest discomfort"
        case .shortnessOfBreath: "Shortness of breath"
        case .swollenAnkles: "Swollen ankles"
        case .dizziness: "Dizziness"
        }
    }
}


/// The weekly check-in of a heart health study: a choice, a multiple choice, a slider and a time on two short pages.
@Instrument
enum HeartCheckIn {
    static let energy = ChoiceQuestion<EnergyLevel>("energy", "How is your energy today?")

    static let symptoms = MultiChoiceQuestion<HeartSymptom>("symptoms", "Which of these did you notice this week?")
        .optional()

    static let walkMinutes = NumberQuestion("walk-minutes", "Minutes walked today")
        .range(0...120)
        .slider(step: 5)

    static let tookMedication = BooleanQuestion("took-medication", "Did you take your medication today?")

    static let medicationTime = DateQuestion.time("medication-time", "At what time?")
        .enabledWhen(tookMedication.isTrue)

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://grovealliance.org/samples/HeartCheckIn")!,
        version: "1.0.0",
        title: "Heart Check-In",
        explainer: "A few questions about your week, once a week."
    ) {
        Section("today", title: "Today") {
            energy
            symptoms
            walkMinutes
        }
        Section("medication", title: "Medication") {
            tookMedication
            medicationTime
        }
    }
}
