//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import SwiftUI


/// What the last page of a questionnaire does, under each of the sheet's completion settings.
///
/// Closing the sheet part-way through asks before discarding, and closing a finished one offers
/// to submit instead; both are the renderer's own, and neither reaches the result handler as a
/// completion.
struct CompletionFlowExample: View {
    @State private var running: Example?

    private var variants: [Example] {
        [
            // A completion page, and a button that says the answers leave the participant's hands.
            Example(ReopenableSurvey.questionnaire, title: "Completion Page, Submit", completionStepConfig: .enable),
            // The same page for a record the participant can reopen: the button reads Done.
            Example(
                ReopenableSurvey.questionnaire,
                title: "Completion Page, Done",
                completionStepConfig: .enable,
                completionAction: .done
            ),
            // The renderer's own default: Submit calls the result handler with no page in between.
            Example(ReopenableSurvey.questionnaire, title: "No Completion Page", completionStepConfig: .disable)
        ]
    }

    var body: some View {
        List {
            ForEach(variants) { variant in
                ExampleRow(example: variant) {
                    running = variant
                }
            }
        }
        .navigationTitle("Completion Flow")
        .navigationBarTitleDisplayMode(.inline)
        .runsQuestionnaires($running)
    }
}
