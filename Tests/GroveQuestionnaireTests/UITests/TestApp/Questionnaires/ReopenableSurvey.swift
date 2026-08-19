//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire


enum IceCreamFlavour: String, QuestionnaireOption {
    case strawberry
    case mango

    var title: String {
        switch self {
        case .strawberry: "Strawberry"
        case .mango: "Mango"
        }
    }
}


/// One question, small enough that answering it twice makes the point of an externally owned
/// ``QuestionnaireResponses``: the answer is still there the second time the sheet opens.
@Instrument
enum ReopenableSurvey {
    static let flavour = ChoiceQuestion<IceCreamFlavour>("flavour", "What's your favourite ice cream flavour?")

    static let questionnaire = Questionnaire(
        url: URL(string: "https://grovealliance.org/samples/ReopenableSurvey")!,
        title: "Reopenable Survey",
        explainer: "One question, answered once and then reopened."
    ) {
        Section("survey") {
            flavour
        }
    }
}
