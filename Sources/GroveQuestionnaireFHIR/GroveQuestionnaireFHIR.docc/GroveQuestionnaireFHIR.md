# ``GroveQuestionnaireFHIR``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Import, present, and export FHIR R4 questionnaires.

## Overview

`GroveQuestionnaireFHIR` connects Grove's questionnaire model with [FHIR R4 Questionnaire](https://hl7.org/fhir/R4/questionnaire.html) and [QuestionnaireResponse](https://hl7.org/fhir/R4/questionnaireresponse.html) resources.
Supported SDC branching, variables, initial and calculated expressions, item metadata, and nested groups survive an import/export round trip.
So do its `useContext` concepts, the codes on groups and questions, and the SDC observation-extraction markings and categories.
So does every language: the base `language` and each `translation` extension on the rendered text.

### Import a Questionnaire

Decode a resource and convert it; the questionnaire is ready to present:

```swift
import GroveQuestionnaireFHIR
import ModelsR4

let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
let questionnaire = try Questionnaire(resource, clock: .live(in: .current))
```

Time functions such as `today()` never read the device's clock, zone or calendar on their own; they read the clock the conversion is given.
While a participant answers, `QuestionnaireClock.live(in:)` reads the wall clock once per state of the answers, in the participant's zone.
A stored response is evaluated at the instant and offset it was authored in, so it yields the same values on any device:

```swift
let questionnaire = try Questionnaire(resource, clock: .authored(storedResponse))
```

A completed or amended response is exported with its calculated answers recomputed at `authored`, so that later evaluation agrees with what was stored.

Import keeps every `translation` extension on the questionnaire's text instead of resolving one language.
The renderer picks the language to show with `Questionnaire.renderingLanguage(for:)`.

### Export a Response

``ResourceBuilder`` publishes a completed questionnaire and its answers as a validated resource pair:

```swift
let pair = try ResourceBuilder().pair(
    from: responses,
    subject: Reference(reference: "Patient/example"),
    renderedIn: locale,
    authored: submittedAt,
    authoredTimeZone: .current
)
upload(pair.questionnaire, pair.response)
```

`renderedIn` is the locale the questionnaire was shown in; the language it selects becomes `QuestionnaireResponse.language`.
Items carry their question text, and coded answers their display, only in the questionnaire's base language, because both must equal the base text.
In a translation, a coded answer is identified by its system and code alone.

`pair(from:)` cross-validates the two resources against the published pair rules, so an inconsistent export fails locally instead of at the receiving system.
Use `response(from:)` instead when the receiver already holds the Questionnaire.
Publishing requires a canonical URL, a Semantic Versioning 2.0.0 version, a base language, and at least one item; the response points at the exact `url|version` and carries one complete business identifier.
`Questionnaire.id` and `QuestionnaireResponse.id` stay empty unless a repository already assigned one and the caller supplies a `RepositoryID`.

### Accept a Pair

Run ``PairValidator`` when accepting a pair from elsewhere:

```swift
let warnings = try PairValidator().validate(
    questionnaire: questionnaire,
    response: response,
    valueSets: resolvedValueSets
)
```

The offline preflight enforces identifiers, hierarchy, answer datatypes, enablement, ValueSet membership, bounds, units, and attachment limits.
It also requires both languages, rejects item text other than the questionnaire's base text and a response language the questionnaire does not offer, and rejects a text that translates into its base language or twice into one language.
Supply every ValueSet an answer or unit constraint references; unresolved terminology fails closed, and the validator never performs a network lookup.
Completed and amended responses that depend on an unevaluated error-severity `targetConstraint` or `enableWhenExpression` are rejected; warning-severity constraints surface in ``ResourcePair/warnings`` instead.

### Boundaries

Questionnaire answers remain QuestionnaireResponse answers: this package does not infer Observations from answers, which requires a separately governed extraction definition.
Custom question kinds participate by conforming to the protocols below; unsupported custom kinds fail export rather than being silently omitted.

## Topics

### Conversion

- ``GroveQuestionnaire/Questionnaire/init(_:clock:using:)``
- ``GroveQuestionnaire/QuestionnaireClock/authored(_:)``
- ``ModelsR4/Questionnaire/init(_:repositoryID:)``
- ``ModelsR4/QuestionnaireResponse/init(_:subject:author:source:status:identifier:repositoryID:renderedIn:authored:authoredTimeZone:)``
- ``ResourceBuilder``
- ``ResourcePair``
- ``PairValidator``
- ``GroveQuestionnaire/Questionnaire/withExpressionEngine(clock:launchContext:)``

### Custom Question Kinds

- ``QuestionKindDefinitionWithFHIRSupport``
- ``QuestionKindDefinitionWithFHIRDecodingSupport``
- ``QuestionKindDefinitionWithFHIREncodingSupport``
- ``GroveQuestionnaire/QuestionnaireResponses/CustomResponseValueProtocolWithFHIRSupport``
