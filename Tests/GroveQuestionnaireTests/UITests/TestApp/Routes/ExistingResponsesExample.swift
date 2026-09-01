//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import GroveQuestionnaireUI
import SwiftUI


/// The sheet normally owns its ``QuestionnaireResponses``; hand it one instead and the answers
/// outlive the sheet, so a questionnaire can be reopened where the participant left it.
struct ExistingResponsesExample: View {
    @State private var responses: QuestionnaireResponses?
    @State private var isAnswering = false
    @State private var isReviewing = false

    var body: some View {
        List {
            Section {
                Button("Answer the Questionnaire") {
                    isAnswering = true
                }
                .accessibilityIdentifier("AnswerQuestionnaire")
                Button("Reopen with the Same Answers") {
                    isReviewing = true
                }
                .accessibilityIdentifier("ReopenQuestionnaire")
                .disabled(responses == nil)
            }

            if let responses {
                Section("Held Answers") {
                    LabeledContent("Flavour", value: responses[ReopenableSurvey.flavour]?.title ?? "—")
                        .accessibilityIdentifier("HeldAnswer:flavour")
                }
            }
        }
        .navigationTitle("Existing Responses")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAnswering) {
            QuestionnaireSheet(ReopenableSurvey.questionnaire) { result in
                switch result {
                case .completed(let responses):
                    self.responses = responses
                case .cancelled:
                    self.responses = nil
                }
                isAnswering = false
            }
        }
        .sheet(isPresented: $isReviewing) {
            if let responses {
                QuestionnaireSheet(ReopenableSurvey.questionnaire, responses: responses, completionAction: .done) { _ in
                    isReviewing = false
                }
            }
        }
    }
}
