# Question Kinds

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->


## Discussion

### Builtin Question Kinds

GroveQuestionnaire supports the following built-in question kinds:

| Question Kind | Description | Response Type |
| ------------- | :---------- | ------------- |
| Instructional | Presents non-interactive, instructional text to the user | *none* |
| Boolean | Asks a yes/no question | `Bool` |
| Choice | Asks the user to select one or more options from a list | `[OptionId]` |
| Free Text | Lets the user write text | `String` |
| DateTime | Asks for a time, or a date, or both | `DateComponents` |
| Numeric | Asks for a number | `Double` |
| File Attachment | Imports a user-selected file | \[``QuestionnaireResponses/CollectedAttachment``\] |
| [Annotate Image](#Image-Annotations) | Prompts the user to mark regions on an image. | ``QuestionnaireResponses/ImageAnnotation`` |

@Row {
    @Column {
        @Image(source: "TextAndChoice", alt: "Screenshot showing choice, boolean and text questions, some of them answered."){
            Single and multiple choice, a drop-down, a yes-or-no question and free text, one card each.
        }
    }
    @Column {
        @Image(source: "DatesAndTimes", alt: "Screenshot showing date, time and date-and-time questions."){
            A date, a time, or both, picked with the system's own controls.
        }
    }
    @Column {
        @Image(source: "Numbers", alt: "Screenshot showing numeric questions as a slider, as fields and as a quantity with a unit."){
            Numbers as a slider, as decimal and integer fields, and as a quantity with its unit.
        }
    }
}

> Tip:
Additional question kinds can be defined via the ``QuestionKindDefinition`` protocol; see also [here](#Custom-Question-Kinds).


#### Image Annotations

The ``AnnotateImageQuestionKind`` prompts the user to annotate certain regions on an image.

The question kind's config (``AnnotateImageConfig``) defines which image should be annotated, and which regions the user is given to choose from.
A region is a label and color, which the user can select to highlight the parts of the image matching that region.

For example, a question asking the user to highlight where they feel pain and/or stiffness would define two regions: one for pain and one for stiffness.

@Row {
    @Column {
        @Image(source: "AnnotateImage", alt: "Screenshot showing a body map on which the participant marks where they feel pain or stiffness."){
            A body map with two regions to choose from; the participant paints the parts of the image that apply.
        }
    }
}

Use the `QuestionKindDefinition` protocol to define a custom question kind, with full support for all functionality offered by GroveQuestionnaire.

Each custom question kind is defined as a Swift struct conforming to the ``QuestionKindDefinition`` protocol.

This struct has the following responsibilities:
- Provide the UI that will be displayed whereever a question of this kind appears in a ``Questionnaire``;
- Validate user-entered responses;
- (Optional) enable support for FHIR-related operations such as creating a Grove ``Questionnaire`` from a [FHIR R4 Questionnaire](https://hl7.org/fhir/R4/questionnaire.html), or converting collected ``QuestionnaireResponses`` into a [FHIR R4 QuestionnaireResponse](https://hl7.org/fhir/R4/questionnaireresponse.html).
  See [`QuestionKindDefinitionWithFHIRSupport`](../../GroveQuestionnaireFHIR/GroveQuestionnaireFHIR.docc/GroveQuestionnaireFHIR.md) for more info.



### Custom Question Kinds

In addition to the built-in question kinds listed above, apps and packages can also define additional, custom question kinds.

A custom question kind is defined via a Swift struct conforming to the ``QuestionKindDefinition`` protocol.

@Row {
    @Column {
        @Image(source: "CustomKind", alt: "Screenshot showing a stopwatch question an app defined itself, rendered like the built-in kinds."){
            A stopwatch, defined by the app: its card, validation and FHIR export work like those of the built-in kinds.
        }
    }
}
This type provides the question kind's UI (used when a matching question is displayed in a ``QuestionnaireSheet``).
It also implements validation and response-handling-related logic.

> Tip:
The ``AnnotateImageQuestionKind``, while being a built-in question kind, is implemented using this API; see its source for an example of the intended usage.


Example: A simple "acknowledge disclaimer" question kind
```swift
/// A question kind that asks the user to consent to a statement.
struct AcknowledgeDisclaimerQuestionKind: QuestionKindDefinition {
    // The config is what allows each instantiation of the question kind to customize the question's input.
    // In this case, it allows us to specify the question's consent text, and the title of the "I Agree" button.
    struct Config: QuestionKindConfig {
        let disclaimerText: String
        let consentButtonTitle: String
    }

    // Creates the view used to display an Acknowledge Disclaimer question within a `QuestionnaireSheet`.
    // In this case, we simply display the text we want the user to acknowledge, and a `Toggle` collecting the user response.
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

    // We can also customize the question kind's response validation logic.
    // In this case, we require that the user consent to the disclaimer, so we reject all non-yes responses.
    // This effectively prevents the user from completing the questionnaire until they have consented to the disclaimer,
    // and the UI displays our validation message next to the question, explaining what's going on.
    static func validate(response: QuestionnaireResponses.Response, for config: Config) -> QuestionnaireResponses.ResponseValidationResult {
        switch response.value.boolValue {
        case true:
            .ok
        case false, nil:
            .invalid(message: "Must agree in order to continue in questionnaire")
        }
    }
}
```


## Topics

- ``Questionnaire/Task/Kind``
- ``QuestionKindDefinition``
- ``AnnotateImageQuestionKind``
