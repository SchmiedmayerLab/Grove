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
        @Image(source: "Overview", alt: "Screenshot showing an FHIR Questionnaire rendered using the QuestionnaireSheet.") {
            A questionnaire rendered by ``QuestionnaireSheet``.
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

## Topics

### Presenting a Questionnaire
- ``QuestionnaireSheet``

### Custom Question Kinds
- <doc:QuestionKindViews>
- ``QuestionKindDefinitionWithViewSupport``
