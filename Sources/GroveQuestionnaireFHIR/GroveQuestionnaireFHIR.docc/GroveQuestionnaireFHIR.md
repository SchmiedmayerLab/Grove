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

`GroveQuestionnaireFHIR` connects Grove's questionnaire model with
[FHIR R4 Questionnaire](https://hl7.org/fhir/R4/questionnaire.html) and
[QuestionnaireResponse](https://hl7.org/fhir/R4/questionnaireresponse.html) resources.
It preserves supported SDC branching, variables, initial expressions, calculated
expressions, item metadata, and nested groups across an import/export round trip.

Decode a resource and install the expression engine before presenting it:

```swift
import GroveQuestionnaireFHIR
import ModelsR4

let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
let questionnaire = try Questionnaire(resource, evaluationInstant: submittedAt)
```

Grove questionnaires can also be published through the normative Grove Questionnaire
0.2 builder. Publishing requires a canonical URL, a Semantic Versioning 2.0.0 version,
and at least one item. The response points to the exact `url|version` and carries one
complete business identifier:

```swift
let pair = try GroveQuestionnaireFHIRBuilder().pair(
    from: responses,
    subject: participant,
    identifier: submissionIdentifier,
    valueSets: resolvedValueSets,
    authored: submittedAt
)
```

`Questionnaire.id` and `QuestionnaireResponse.id` are omitted unless a repository has
already assigned them and the caller supplies a `GroveFHIRRepositoryID`.
Use ``GroveQuestionnaireFHIRPairValidator`` when accepting a pair. Its offline preflight
enforces the exact canonical and business identifier, hierarchy, answer datatypes,
enablement and required-item state, inline and resolved ValueSet membership, length and
value bounds, decimal precision, units, attachment limits, repeated-answer limits, and
exclusive options. Supply every ValueSet referenced by an answer or unit constraint;
unresolved terminology fails closed and the validator never performs a network lookup.

Completed and amended responses that depend on an unevaluated error-severity
`targetConstraint` or `enableWhenExpression` are rejected. Warning-severity constraints
are returned in ``GroveQuestionnaireFHIRPair/warnings`` so the form filler can surface and
evaluate them without misrepresenting the response as invalid. The repository conformance
workflow additionally runs the official R4 validator, the SDC package, the Grove
Questionnaire 0.2 package, terminology checks, and the IG's cross-resource validator.

Questionnaire answers remain QuestionnaireResponse answers. This package intentionally
does not infer Observations from arbitrary answers; a separately governed extraction
definition is required for that clinical transformation.

Custom question kinds can participate by conforming their definitions and response
values to the FHIR support protocols below. Unsupported custom kinds fail export rather
than being silently omitted.

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
