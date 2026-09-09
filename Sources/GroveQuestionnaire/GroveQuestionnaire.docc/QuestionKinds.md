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

> Tip:
Additional question kinds can be defined via the ``QuestionKindDefinition`` protocol; see also [here](#Custom-Question-Kinds).


#### Image Annotations

The `AnnotateImageQuestionKind` prompts the user to annotate certain regions on an image.

The question kind's config (`AnnotateImageConfig`) defines which image should be annotated, and which regions the user is given to choose from.
A region is a label and color, which the user can select to highlight the parts of the image matching that region.

For example, a question asking the user to highlight where they feel pain and/or stiffness would define two regions: one for pain and one for stiffness.

Use the `QuestionKindDefinition` protocol to define a custom question kind, with full support for all functionality offered by GroveQuestionnaire.

Each custom question kind is defined as a Swift struct conforming to the ``QuestionKindDefinition`` protocol.

This struct has the following responsibilities:
- Provide the UI that will be displayed whereever a question of this kind appears in a ``Questionnaire``;
- Validate user-entered responses;
- (Optional) enable support for FHIR-related operations such as creating a Grove ``Questionnaire`` from a [FHIR R4 Questionnaire](https://hl7.org/fhir/R4/questionnaire.html), or converting collected ``QuestionnaireResponses`` into a [FHIR R4 QuestionnaireResponse](https://hl7.org/fhir/R4/questionnaireresponse.html).
  See [`QuestionKindDefinitionWithFHIRSupport`](../../GroveQuestionnaireFHIR/GroveQuestionnaireFHIR.docc/GroveQuestionnaireFHIR.md) for more info.



### Custom Question Kinds

Beyond the built-in kinds, an app or package can define its own. A custom question kind is a
Swift type conforming to ``QuestionKindDefinition``, which gives it a ``QuestionKindConfig``
to carry per-question settings and a `validate(response:for:)` that decides whether an answer
is acceptable.

Defining a kind here says what it *is* and what counts as a valid answer — nothing about how it
looks, so a custom kind travels with the instrument and validates wherever the instrument does.

> Tip: A kind that is shown on screen also conforms to `QuestionKindDefinitionWithViewSupport`
in `GroveQuestionnaireUI`, which adds the SwiftUI view it renders. That module's
"Giving a Question Kind a View" article works through an example.

The `AnnotateImageQuestionKind` is built this way: its config and validation live here, and its
editor lives in `GroveQuestionnaireUI`.


## Topics

- ``Questionnaire/Task/Kind``
- ``QuestionKindDefinition``
