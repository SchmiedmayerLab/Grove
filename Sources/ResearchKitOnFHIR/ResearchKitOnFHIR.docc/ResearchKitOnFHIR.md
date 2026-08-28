# ``ResearchKitOnFHIR``

ResearchKitOnFHIR is a framework that allows you to use FHIR questionnaires with ResearchKit.

<!--
                  
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

## Features

ResearchKitOnFHIR is a framework that allows you to use [FHIR Questionnaires](https://www.hl7.org/fhir/questionnaire.html) with ResearchKit to create healthcare surveys on iOS based on the [HL7 Structured Data Capture Implementation Guide](http://build.fhir.org/ig/HL7/sdc/)

It allows you to:
- Convert [FHIR Questionnaires](https://www.hl7.org/fhir/questionnaire.html) into ResearchKit tasks
- Serialize results into [FHIR QuestionnaireResponses](https://www.hl7.org/FHIR/questionnaireresponse.html)
- Supports survey skip-logic by converting FHIR `enableWhen` conditions into ResearchKit navigation rules
- Supports answer validation during entry
- Supports contained [FHIR ValueSets](https://www.hl7.org/fhir/valueset.html) as answer options

### FHIR<-> ResearchKit Conversion

| FHIR R4 [QuestionnaireItemType](https://www.hl7.org/fhir/valueset-item-type.html) | ResearchKit Type | FHIR Response Type
|------------------------------|-----------------------------|--------------------------|
| [display](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-display) | [ORKInstructionStep](http://researchkit.org/docs/Classes/ORKInstructionStep.html) | *none*
| [group](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-group) | [ORKFormStep](http://researchkit.org/docs/Classes/ORKFormStep.html) | *none*
| [boolean](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-boolean) | [ORKBooleanAnswerFormat](http://researchkit.org/docs/Classes/ORKBooleanAnswerFormat.html) | valueBoolean
| [choice](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-choice) | [ORKTextChoice](http://researchkit.org/docs/Classes/ORKTextChoice.html); `repeats=true` selects multiple-choice | valueCoding
| [date](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-date) | [ORKDateAnswerFormat](http://researchkit.org/docs/Classes/ORKDateAnswerFormat.html)(style: [ORKDateAnswerStyle.date](http://researchkit.org/docs/Constants/ORKDateAnswerStyle.html) | valueDate 
| [dateTime](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-dateTime) | [ORKDateAnswerFormat](http://researchkit.org/docs/Classes/ORKDateAnswerFormat.html)(style: [ORKDateAnswerStyle.dateAndTime](http://researchkit.org/docs/Constants/ORKDateAnswerStyle.html) | valueDateTime 
| [time](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-time) | [ORKTimeOfDayAnswerFormat](http://researchkit.org/docs/Classes/ORKTimeOfDayAnswerFormat.html) | valueTime 
| [decimal](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-decimal) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).decimalAnswerFormat | valueDecimal 
| [quantity](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-quantity) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).decimalAnswerFormat(withUnit: quantityUnit) | valueQuantity 
| [integer](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-integer) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).integerAnswerFormat | valueInteger 
| [text](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-text) | [ORKTextAnswerFormat](http://researchkit.org/docs/Classes/ORKTextAnswerFormat.html) | valueString 
| [string](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-string) | [ORKTextAnswerFormat](http://researchkit.org/docs/Classes/ORKTextAnswerFormat.html) | valueString 

### Navigation Rules

The following table describes how the FHIR [enableWhen](https://www.hl7.org/fhir/questionnaire-definitions.html#Questionnaire.item.enableWhen) is converted to a ResearchKit [ORKSkipStepNavigationRule](http://researchkit.org/docs/Classes/ORKSkipStepNavigationRule.html) for each supported type and operator. (The conversion is performed by constructing an ORKResultPredicate from the enableWhen expression and negating it.)

| FHIR R4 [QuestionnaireItemType](https://www.hl7.org/fhir/valueset-item-type.html) | Supported [QuestionnaireItemOperators](https://www.hl7.org/fhir/valueset-questionnaire-enable-operator.html) | ResearchKit [ORKResultPredicate](http://researchkit.org/docs/Classes/ORKResultPredicate.html) |
| ---------------------------- | ------------------- | ------------------------------ |
| boolean | =, != | .predicateForBooleanQuestionResult
| integer | =, !=, <=, >= | .predicateForNumericQuestionResult
| decimal | =, !=, <=, >= | .predicateForNumericQuestionResult
| date | >, < | .predicateForDateQuestionResult
| coding | =, != | .predicateForChoiceQuestionResult


## Usage
The `Example` directory contains an Xcode project that demonstrates how to create a ResearchKit task from a FHIR Questionnaire, and extract the results in the form of a FHIR QuestionnaireResponse.

### Converting from FHIR to ResearchKit

#### 1. Instantiate a FHIR Questionnaire from JSON

```swift
let data = <FHIR JSON data>
var questionnaire: Questionnaire?
do {
    questionnaire = try JSONDecoder().decode(Questionnaire.self, from: data)
} catch {
    print("Could not decode the FHIR questionnaire": \(error)")
}
```

#### 2. Create a ResearchKit Navigable Task from the FHIR Questionnaire

```swift
var task: ORKNavigableOrderedTask?
do {
    let questionnaire = try require(questionnaire)
    task = try ORKNavigableOrderedTask(
        questionnaire: questionnaire,
        evaluationInstant: evaluationInstant,
        evaluationTimeZone: evaluationTimeZone
    )
} catch {
    print("Error creating task: \(error)")
}
```

Now you can present the task as described in the [ResearchKit documentation](https://github.com/SchmiedmayerLab/ResearchKit#4-present-the-task).

### Converting ResearchKit Task Results to FHIR QuestionnaireResponse

In your class that implements the `ORKTaskViewControllerDelegateProtocol`, convert a result with the same immutable source `Questionnaire` that produced the task. Conformant export requires that source to claim exactly the Grove Questionnaire profile. The context also requires a stable response identifier, a typed Patient subject, and explicit authored time facts. This lets the converter rebuild the Questionnaire's exact hierarchy and prevents retries from inventing identity or timestamps. The output directly claims the Grove QuestionnaireResponse profile and records electronic completion mode.

```swift
func taskViewController(
    _ taskViewController: ORKTaskViewController, 
    didFinishWith reason: ORKTaskViewControllerFinishReason, 
    error: Error?
) {
    switch reason {
    case .completed:
        do {
            let participantID = try BusinessIdentifier(
                system: "https://example.org/fhir/identifier/participant",
                value: participantIdentifier
            )
            let subject = Reference(
                identifier: participantID.fhirIdentifier,
                type: "Patient".asFHIRURIPrimitive()
            )
            let context = try ResearchKitFHIRConversionContext(
                questionnaire: questionnaire,
                responseIdentifier: responseIdentifier,
                subject: subject,
                authored: completionInstant,
                authoredTimeZone: studyTimeZone,
                attachmentResolver: stageAttachment
            )
            let fhirResponse = try taskViewController.result.fhirResponse(using: context)
            // Persist or exchange fhirResponse.
        } catch {
            // Treat conversion or attachment-staging failure as a failed publication.
        }
    default:
        break
    }
}
```

`attachmentResolver` is called only for an `ORKFileResult`. It must replace the local file with embedded bytes or a durable HTTP(S) location and return `contentType`, SHA-1 `hash`, and `size`. Local `file://` URLs are never placed in the FHIR response.

ResearchKit's image-capture step produces one file result. A Grove Questionnaire may legally allow repeated attachment answers, but this adapter rejects that layout with a precise unsupported-layout error instead of silently dropping all but one attachment. Repeated `choice` and `open-choice` items are supported; their ResearchKit cardinality comes from FHIR `Questionnaire.item.repeats`, not presentation-only `itemControl` metadata.
