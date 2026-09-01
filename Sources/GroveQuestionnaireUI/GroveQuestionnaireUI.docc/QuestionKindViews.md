# Giving a Question Kind a View

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

How a custom question kind is rendered and answered.

## Discussion

A question kind is defined in `GroveQuestionnaire` by conforming to `QuestionKindDefinition`,
which carries its configuration and decides whether an answer is valid. That much is
platform-neutral: it travels with the instrument and validates wherever the instrument does.

A kind that is also *shown* conforms to ``QuestionKindDefinitionWithViewSupport``, which adds the
one thing the model cannot express — the SwiftUI view the participant answers in.

Splitting it this way keeps a kind usable off-screen. A questionnaire using a custom kind can be
converted, scored, and stored on a server that has no view layer at all.

> Tip: The built-in `AnnotateImageQuestionKind` is written exactly like this — its config and
validation live in `GroveQuestionnaire`, its editor here.

### A worked example

An "acknowledge disclaimer" kind: the model side declares what it asks and what counts as an
answer, and the view side draws it.

```swift
// In GroveQuestionnaire terms: what the question is, and what a valid answer looks like.
struct AcknowledgeDisclaimerQuestionKind: QuestionKindDefinition {
    // The config lets each use of the kind customize the question.
    struct Config: QuestionKindConfig {
        let disclaimerText: String
        let consentButtonTitle: String
    }

    // Require consent, so the questionnaire cannot be completed until the participant agrees.
    // The UI shows this message next to the question.
    static func validate(response: QuestionnaireResponses.Response, for config: Config) -> QuestionnaireResponses.ResponseValidationResult {
        switch response.value.boolValue {
        case true:
            .ok
        case false, nil:
            .invalid(message: "Must agree in order to continue in questionnaire")
        }
    }
}


// The view half, which only this module needs.
extension AcknowledgeDisclaimerQuestionKind: QuestionKindDefinitionWithViewSupport {
    static func makeView(for task: Questionnaire.Task, using config: Config, response: Binding<QuestionnaireResponses.Response>) -> some View {
        Text(config.disclaimerText)
        Toggle(config.consentButtonTitle, isOn: Binding<Bool> {
            response.value.boolValue.wrappedValue ?? false
        } set: { newValue in
            response.value.boolValue.wrappedValue = newValue
        })
        .bold()
        .onChange(of: response.value.wrappedValue == .none, initial: true) { _, newValue in
            if newValue {
                response.value.boolValue.wrappedValue = false
            }
        }
    }
}
```

The view is placed into a `Section` within a `Form`, so each element becomes a row.

## Topics

### Supporting Types
- ``QuestionKindDefinitionWithViewSupport``
