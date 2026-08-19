//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import SwiftUI


/// Questionnaires declared in Swift, where a question is a value the rest of the code can name.
///
/// Both instruments carry the `@Instrument` macro, which checks at compile time that every
/// declared question is placed exactly once and that no two share a linkId.
struct SwiftDSLRoute: View {
    var body: some View {
        ExampleCatalog(route: .swiftDSL, groups: [
            ExampleGroup("Instruments", [
                // Typed option sets, a group gated as a whole, and a score summed from option weights.
                // The showcase instrument asks for a completion page; the rest take the default.
                Example(.sleepCheckIn, completionStepConfig: .enable),
                // Follow-up questions asked once per selected option, written with .followUp.
                Example(ActivityLog.questionnaire)
            ]),
            ExampleGroup("Reference", [
                // Every question kind the DSL spells, over three pages, with length and range rules.
                Example(QuestionKinds.questionnaire)
            ])
        ])
    }
}
