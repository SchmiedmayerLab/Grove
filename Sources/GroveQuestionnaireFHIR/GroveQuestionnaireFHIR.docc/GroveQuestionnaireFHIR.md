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

### Import a Questionnaire

Decode a resource and convert it; the questionnaire is ready to present:

```swift
import GroveQuestionnaireFHIR
import ModelsR4

let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
let questionnaire = try Questionnaire(resource)
```

Clock-sensitive expressions such as `today()` use the wall clock by default.
Pass `evaluationInstant:` to make a conversion reproducible, for example in tests or when re-evaluating a stored submission:

```swift
let questionnaire = try Questionnaire(resource, evaluationInstant: submittedAt)
```

### Export a Response

``GroveQuestionnaireFHIRBuilder`` publishes a completed questionnaire and its answers as a validated resource pair:

```swift
let pair = try GroveQuestionnaireFHIRBuilder().pair(
    from: responses,
    subject: Reference(reference: "Patient/example")
)
upload(pair.questionnaire, pair.response)
```

`pair(from:)` cross-validates the two resources against the published pair rules, so an inconsistent export fails locally instead of at the receiving system.
Use `response(from:)` instead when the receiver already holds the Questionnaire.
Publishing requires a canonical URL, a Semantic Versioning 2.0.0 version, and at least one item; the response points at the exact `url|version` and carries one complete business identifier.
`Questionnaire.id` and `QuestionnaireResponse.id` stay empty unless a repository already assigned one and the caller supplies a `GroveFHIRRepositoryID`.

### Accept a Pair

Run ``GroveQuestionnaireFHIRPairValidator`` when accepting a pair from elsewhere:

```swift
let warnings = try GroveQuestionnaireFHIRPairValidator().validate(
    questionnaire: questionnaire,
    response: response,
    valueSets: resolvedValueSets
)
```

The offline preflight enforces identifiers, hierarchy, answer datatypes, enablement, ValueSet membership, bounds, units, and attachment limits.
Supply every ValueSet an answer or unit constraint references; unresolved terminology fails closed, and the validator never performs a network lookup.
Completed and amended responses that depend on an unevaluated error-severity `targetConstraint` or `enableWhenExpression` are rejected; warning-severity constraints surface in ``GroveQuestionnaireFHIRPair/warnings`` instead.

### Boundaries

Questionnaire answers remain QuestionnaireResponse answers: this package does not infer Observations from answers, which requires a separately governed extraction definition.
Custom question kinds participate by conforming to the protocols below; unsupported custom kinds fail export rather than being silently omitted.

## Topics

### Conversion

- ``GroveQuestionnaire/Questionnaire/init(_:evaluationInstant:using:)``
- ``ModelsR4/Questionnaire/init(_:repositoryID:)``
- ``ModelsR4/QuestionnaireResponse/init(_:subject:author:source:status:identifier:repositoryID:authored:)``
- ``GroveQuestionnaireFHIRBuilder``
- ``GroveQuestionnaireFHIRPair``
- ``GroveQuestionnaireFHIRPairValidator``
- ``GroveQuestionnaire/Questionnaire/withExpressionEngine(evaluationInstant:launchContext:)``

### Custom Question Kinds

- ``QuestionKindDefinitionWithFHIRSupport``
- ``QuestionKindDefinitionWithFHIRDecodingSupport``
- ``QuestionKindDefinitionWithFHIREncodingSupport``
- ``GroveQuestionnaire/QuestionnaireResponses/CustomResponseValueProtocolWithFHIRSupport``
