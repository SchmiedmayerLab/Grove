//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import SwiftUI


/// A question kind an app brings itself: a disclaimer the participant has to accept.
///
/// The validation rule is what makes it more than a boolean — a section holding an
/// unaccepted disclaimer never counts as complete, and the message is what the renderer
/// shows beneath the question.
struct AcknowledgementQuestionKind: QuestionKindDefinition {
    struct Config: QuestionKindConfig {
        let disclaimerText: String
        let consentButtonTitle: String
    }

    static func makeView(
        for task: Questionnaire.Task,
        using config: Config,
        response: Binding<QuestionnaireResponses.Response>
    ) -> some View {
        Text(config.disclaimerText)
        Toggle(config.consentButtonTitle, isOn: Binding {
            response.value.boolValue.wrappedValue ?? false
        } set: { newValue in
            response.value.boolValue.wrappedValue = newValue
        })
        .bold()
        .onChange(of: response.value.wrappedValue == .none, initial: true) { _, isUnanswered in
            if isUnanswered {
                response.value.boolValue.wrappedValue = false
            }
        }
    }

    static func validate(
        response: QuestionnaireResponses.Response,
        for config: Config
    ) -> QuestionnaireResponses.ResponseValidationResult {
        switch response.value.boolValue {
        case true:
            .ok
        case false, nil:
            .invalid(message: "Must agree in order to continue in questionnaire")
        }
    }
}
