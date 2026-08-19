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
let questionnaire = try Questionnaire(resource).withExpressionEngine()
```

Grove questionnaires can also be published as FHIR resources, and collected answers
can be submitted with stable identity and authorship metadata:

```swift
let fhirQuestionnaire = try ModelsR4.Questionnaire(questionnaire)
let response = try ModelsR4.QuestionnaireResponse(
    responses,
    subject: participant,
    identifier: submissionIdentifier,
    authored: submittedAt
)
```

Custom question kinds can participate by conforming their definitions and response
values to the FHIR support protocols below. Unsupported custom kinds fail export rather
than being silently omitted.

## Topics

### Conversion

- ``GroveQuestionnaire/Questionnaire/init(_:using:)``
- ``ModelsR4/Questionnaire/init(_:)``
- ``ModelsR4/QuestionnaireResponse/init(_:subject:author:source:status:identifier:authored:)``
- ``GroveQuestionnaire/Questionnaire/withExpressionEngine(launchContext:)``

### Custom Question Kinds

- ``QuestionKindDefinitionWithFHIRSupport``
- ``QuestionKindDefinitionWithFHIRDecodingSupport``
- ``QuestionKindDefinitionWithFHIREncodingSupport``
- ``GroveQuestionnaire/QuestionnaireResponses/CustomResponseValueProtocolWithFHIRSupport``
