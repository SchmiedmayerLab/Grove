//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import ModelsR4


enum Activity: String, QuestionnaireOption {
    case running
    case cycling
    case swimming
    case strength

    static let system = URL(string: "https://grovealliance.org/samples/CodeSystem/Activity")

    var title: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .strength: "Strength training"
        }
    }
}


enum Cadence: String, QuestionnaireOption {
    case daily
    case mostDays = "most-days"
    case weekly
    case occasionally

    var title: String {
        switch self {
        case .daily: "Daily"
        case .mostDays: "Most days"
        case .weekly: "About once a week"
        case .occasionally: "Less often"
        }
    }
}


/// Follow-up questions, asked once per selected option.
///
/// `.followUp` nests its questions beneath the choice they belong to; the answers export as
/// `answer.item` — FHIR's own "asked in the context of this answer". Every selected activity
/// is asked the same pair, on a pushed page.
@Instrument
enum ActivityLog {
    static let activities = MultiChoiceQuestion<Activity>("activities", "Which of these did you do this week?")
        .subtitle("Pick as many as apply; each one asks a couple of follow-ups.")

    static let cadence = ChoiceQuestion<Cadence>("cadence", "How often?")

    static let minutes = NumberQuestion.integer("minutes", "For how many minutes at a time?")
        .range(0...300)

    static let notes = TextQuestion("notes", "Anything worth noting about your week?")
        .optional()

    static let questionnaire = Questionnaire(
        url: URL(string: "https://grovealliance.org/samples/ActivityLog")!,
        version: "1.0.0",
        title: "Activity Log",
        explainer: "One question that asks itself again for every activity you pick."
    ) {
        Section("week", title: "Your Week") {
            activities.followUp {
                cadence
                minutes
            }
            notes
        }
    }
}
