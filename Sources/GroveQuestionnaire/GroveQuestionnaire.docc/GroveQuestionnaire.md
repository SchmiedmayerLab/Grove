# ``GroveQuestionnaire``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Declare questionnaires in Swift, present them, and collect FHIR-conformant responses.

## Overview

A questionnaire your app defines is written in Swift: the questions, their branching, and
their scoring are ordinary declarations the compiler checks. Questionnaires published by
someone else arrive as [FHIR R4 Questionnaires](https://hl7.org/fhir/R4/questionnaire.html)
and are imported instead.

Both paths produce the same ``Questionnaire``, render through the same
``QuestionnaireSheet``, and export the same conformant FHIR `Questionnaire` and
`QuestionnaireResponse`.

@Row {
    @Column {
        @Image(source: "Overview", alt: "Screenshot showing an FHIR Questionnaire rendered using the Questionnaire module."){
            A questionnaire rendered by ``QuestionnaireSheet``.
        }
    }
}


## Setup

Add the Grove Questionnaire Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) and set up the core Grove infrastructure.


## Authoring in Swift

An instrument is an enum holding its questions and the questionnaire that places them.
Here is the PHQ-2, scored and with a follow-up that only appears when it needs to:

```swift
import GroveQuestionnaire


enum Frequency: String, ScoredOption {
    case notAtAll = "not-at-all"
    case severalDays = "several-days"
    case moreThanHalf = "more-than-half"
    case nearlyEveryDay = "nearly-every-day"

    static let system = URL(string: "https://example.org/fhir/CodeSystem/phq-scale")

    var title: String {
        switch self {
        case .notAtAll: "Not at all"
        case .severalDays: "Several days"
        case .moreThanHalf: "More than half the days"
        case .nearlyEveryDay: "Nearly every day"
        }
    }

    var score: Decimal {
        switch self {
        case .notAtAll: 0
        case .severalDays: 1
        case .moreThanHalf: 2
        case .nearlyEveryDay: 3
        }
    }
}


@Instrument
enum PHQ2 {
    static let interest = ChoiceQuestion<Frequency>("phq2-1", "Little interest or pleasure in doing things")
        .prefix("1.")
    static let mood = ChoiceQuestion<Frequency>("phq2-2", "Feeling down, depressed, or hopeless")
        .prefix("2.")
    static let total = NumberQuestion("phq2-total", "Score")
        .calculated(.sumOfWeights(of: interest, mood))
        .readOnly()
        .hidden()
        .optional()
    static let followUp = TextQuestion("phq2-follow-up", "What has been troubling you?")
        .enabledWhen(mood.selected(.nearlyEveryDay) || interest.selected(.nearlyEveryDay))
        .optional()

    static let questionnaire = Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/phq2")!,
        version: "1.0.0",
        title: "PHQ-2"
    ) {
        Section("phq2", title: "Over the last two weeks") {
            Instruction("phq2-intro", "How often have you been bothered by the following problems?")
            interest
            mood
            total
            followUp
        }
    }
}
```

Present it, and read the answers back through the same declarations that made them:

```swift
import GroveQuestionnaire
import GroveQuestionnaireFHIR
import SwiftUI


struct DailyCheckIn: View {
    @State private var isPresented = false
    private let evaluationInstant = Date()

    var body: some View {
        Button("Answer the PHQ-2") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            QuestionnaireSheet(try! PHQ2.questionnaire.withExpressionEngine(
                evaluationInstant: evaluationInstant
            )) { result in
                guard case .completed(let responses) = result else {
                    return
                }
                let score = responses[PHQ2.total]        // Double?
                let mood = responses[PHQ2.mood]         // Frequency?
                // ... store the responses
            }
        }
    }
}
```

`responses[PHQ2.mood]` is a `Frequency?`, not a string looked up by linkId, and
`.selected(.nearlyEveryDay)` cannot name an option the scale does not have.
<doc:AuthoringQuestionnaires> covers the full vocabulary: question kinds, groups,
conditions, scoring, and what `@Instrument` rejects at build time.


## Importing FHIR

Import a FHIR questionnaire when the instrument is not yours to define: a licensed
instrument distributed as a FHIR resource, or one a study server hands the app at runtime.

```swift
import GroveQuestionnaireFHIR
import ModelsR4

let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
let evaluationInstant = Date()
let questionnaire = try Questionnaire(resource, evaluationInstant: evaluationInstant)
```

FHIR import enables supported SDC conditions, initial values, and calculated FHIRPath
expressions. The explicit evaluation instant makes `now()`, `today()`, lifecycle
warnings, and repeated exports reproducible.

The result is an ordinary ``Questionnaire``, so it renders the same way, and the collected
answers export as a `QuestionnaireResponse`:

```swift
QuestionnaireSheet(questionnaire) { result in
    guard case .completed(let responses) = result else {
        return
    }
    do {
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            subject: participant,
            authored: submittedAt
        )
        // ... upload the response
    } catch {
        // ... report the failure
    }
}
```

If the app was written against a specific instrument, declare it in Swift anyway and check
the imported resource against it once, before typed handles read from it. A questionnaire
that drifted from the declaration otherwise surfaces as answers that are quietly always
`nil`:

```swift
try questionnaire.checkDeclaration(of: PHQ2.self)
```

## Topics

### Authoring
- <doc:AuthoringQuestionnaires>
- ``Instrument()``
- ``Questionnaire``
- <doc:QuestionKinds>

### Responses
- ``QuestionnaireResponses``

### UI
- ``QuestionnaireSheet``
