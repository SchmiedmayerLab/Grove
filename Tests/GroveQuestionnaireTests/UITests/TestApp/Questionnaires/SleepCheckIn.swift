//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import GroveQuestionnaireFHIR


/// How often something happened over the past seven nights.
enum SleepFrequency: String, ScoredOption {
    case never
    case someNights = "some-nights"
    case mostNights = "most-nights"
    case everyNight = "every-night"

    static let system = URL(string: "https://grovealliance.org/samples/CodeSystem/SleepFrequency")

    var title: String {
        switch self {
        case .never: "Never"
        case .someNights: "Some nights"
        case .mostNights: "Most nights"
        case .everyNight: "Every night"
        }
    }

    var score: Decimal {
        switch self {
        case .never: 0
        case .someNights: 1
        case .mostNights: 2
        case .everyNight: 3
        }
    }
}


/// What the participant drank in the three hours before going to bed.
enum EveningDrink: String, QuestionnaireOption {
    case nothing
    case caffeinated
    case alcohol

    static let system = URL(string: "https://grovealliance.org/samples/CodeSystem/EveningDrink")

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .caffeinated: "Something caffeinated"
        case .alcohol: "Alcohol"
        }
    }
}


/// A short scored sleep instrument, declared with the Swift DSL.
///
/// Typed option sets with weights, a group gated as a whole, a follow-up keyed on a single
/// option, and a score computed from the weights the options carry.
@Instrument
enum SleepCheckIn {
    static let hadTrouble = BooleanQuestion("sleep-trouble", "Did you have trouble sleeping this past week?")

    static let fallingAsleep = ChoiceQuestion<SleepFrequency>("falling-asleep", "Lay awake for more than half an hour")
    static let wakingUp = ChoiceQuestion<SleepFrequency>("waking-up", "Woke up in the middle of the night")
    static let daytimeTiredness = ChoiceQuestion<SleepFrequency>("daytime-tiredness", "Felt tired during the day")

    /// Optional because the participant cannot answer it: a required question nobody can
    /// fill in would keep the section from ever completing.
    static let score = NumberQuestion("sleep-score", "Sleep score (0–9)")
        .calculated(.sumOfWeights(of: fallingAsleep, wakingUp, daytimeTiredness))
        .readOnly()
        .optional()

    static let advisory = Instruction("advisory", "A score of **5 or more** is worth bringing up at your next visit.")
        .enabledWhen(score >= 5)

    static let recentNights = Group("recent-nights", title: "Recent nights") {
        Instruction("recent-nights-intro", "In the past week, how often did each of these happen?")
        fallingAsleep
        wakingUp
        daytimeTiredness
        score
        advisory
    }
    .enabledWhen(hadTrouble.isTrue)

    static let sleptWell = TextQuestion("slept-well", "What do you think helped you sleep?")
        .enabledWhen(hadTrouble.isFalse)
        .optional()

    static let eveningDrink = ChoiceQuestion<EveningDrink>("evening-drink", "What did you drink in the three hours before bed?")

    static let drinkDetails = TextQuestion("drink-details", "Which drink was it, and how late?")
        .enabledWhen(eveningDrink.selected(.caffeinated))
        .optional()

    static let screenMinutes = NumberQuestion.integer("screen-minutes", "Minutes spent looking at a screen in bed")
        .range(0...240)
        .help("A rough estimate is fine.")

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://grovealliance.org/samples/SleepCheckIn")!,
        version: "1.0.0",
        title: "Sleep Check-In",
        explainer: "A handful of questions about the past seven nights."
    ) {
        Section("week", title: "Your Week") {
            Instruction("intro", "Answer for the **past seven nights**.")
            hadTrouble
            recentNights
            sleptWell
        }
        Section("habits", title: "Evening Habits") {
            eveningDrink
            drinkDetails
            screenMinutes
        }
    }
}


extension GroveQuestionnaire.Questionnaire {
    /// The Swift-declared ``SleepCheckIn`` instrument, with the engine that evaluates its score.
    static let sleepCheckIn: GroveQuestionnaire.Questionnaire = {
        try! SleepCheckIn.questionnaire.checkDeclaration(of: SleepCheckIn.self)
        return try! SleepCheckIn.questionnaire.withExpressionEngine()
    }()
}
