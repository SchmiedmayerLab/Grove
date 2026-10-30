# ``GroveQuestionnaireUI``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Presents a questionnaire on screen and collects the answers.

## Overview

`GroveQuestionnaire` models an instrument: its questions, their branching, their scoring, and the
answers collected for it. This module renders one. Present ``QuestionnaireSheet`` with a
questionnaire and it runs the instrument — laying out each section, applying the authored
conditions as answers arrive, showing validation messages, and handing back the responses when
the participant finishes.

@Row {
    @Column {
        @Image(source: "Overview", alt: "Screenshot showing the first page of a questionnaire rendered by the Questionnaire module."){
            A questionnaire rendered by ``QuestionnaireSheet``, one question to a card.
        }
    }
    @Column {
        @Image(source: "Validation", alt: "Screenshot showing an unanswered question marked in red after the participant tried to continue."){
            Continuing early marks what still needs an answer and brings the page back to it.
        }
    }
    @Column {
        @Image(source: "Score", alt: "Screenshot showing a score computed from the chosen options, and an instruction that appeared once it crossed a threshold."){
            Questions follow from answers: a score computed from the option weights updates as they are chosen, and an instruction appears once it crosses a threshold.
        }
    }
}

> Tip: Authoring an instrument, importing one from FHIR, and reading the collected answers are all
described in the `GroveQuestionnaire` documentation. This module only puts one on screen.

## Setup

Add `GroveQuestionnaireUI` alongside `GroveQuestionnaire` in your target's dependencies. The UI
module re-exports the model, so a view file needs only the one import:

```swift
import GroveQuestionnaireUI
```

To offer **Take Photo** for image attachment questions on iOS, add a nonempty `NSCameraUsageDescription` to your app's `Info.plist` explaining why the questionnaire needs camera access.
The camera option appears only when that description is present and a camera is available.
Apps without it can still import photos and files.

## Presenting a Questionnaire

``QuestionnaireSheet`` takes a questionnaire and a completion handler. The handler receives the
collected `QuestionnaireResponses`, which are subscripted by the question declarations
themselves:

```swift
QuestionnaireSheet(Screener.questionnaire) { result in
    guard case .completed(let responses) = result else {
        return
    }
    let consented = responses[Screener.consent]           // Bool?
    let age = responses[Screener.age]                     // Double?
}
```

The sheet renders in one language for the whole questionnaire: `Questionnaire.renderingLanguage(for:)` selects it from the environment's `locale`.
Export the responses with that same locale, so the response names the language the participant saw.

Every built-in question kind renders as a card of its own:

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

@Row {
    @Column {
        @Image(source: "AnnotateImage", alt: "Screenshot showing a body map on which the participant marks where they feel pain or stiffness."){
            A body map with two regions to choose from; the participant paints the parts of the image that apply.
        }
    }
}

## Topics

### Presenting a Questionnaire

The sheet shows a progress bar unless asked otherwise; a questionnaire that is one step of a longer flow passes
`progressRange:` to fill only its part of it. Hints such as "Select all that apply" are off unless asked for.
``QuestionnaireProgress`` takes over from `QuestionProgressConfig`, which is deprecated.

- ``QuestionnaireSheet``
- ``QuestionnaireProgress``
- ``QuestionnaireHints``

### Custom Question Kinds
- <doc:QuestionKindViews>
- ``QuestionKindDefinitionWithViewSupport``
