<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# ResearchKitOnFHIR


ResearchKitOnFHIR is a framework that allows you to use [FHIR Questionnaires](https://www.hl7.org/fhir/questionnaire.html) with ResearchKit to create healthcare surveys on iOS based on the [HL7 Structured Data Capture Implementation Guide](http://build.fhir.org/ig/HL7/sdc/)

For more information, please refer to the [API documentation](ResearchKitOnFHIR.docc/ResearchKitOnFHIR.md).


## Features

- Converts [FHIR Questionnaires](https://www.hl7.org/fhir/questionnaire.html) into ResearchKit tasks
- Serializes results into [FHIR QuestionnaireResponses](https://www.hl7.org/FHIR/questionnaireresponse.html)
- Supports survey skip-logic by converting FHIR `enableWhen` conditions into ResearchKit navigation rules
- Supports answer validation during entry
- Supports contained [FHIR ValueSets](https://www.hl7.org/fhir/valueset.html) as answer options


### FHIR <-> ResearchKit Conversion

| FHIR R4 [QuestionnaireItemType](https://www.hl7.org/fhir/valueset-item-type.html) | ResearchKit Type | FHIR Response Type
|------------------------------|-----------------------------|--------------------------|
| [attachment](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-attachment) | [ORKImageCaptureStep](http://researchkit.org/docs/Classes/ORKImageCaptureStep.html) | valueAttachment
| [boolean](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-boolean) | [ORKBooleanAnswerFormat](http://researchkit.org/docs/Classes/ORKBooleanAnswerFormat.html) | valueBoolean
| [choice](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-choice) | [ORKTextChoice](http://researchkit.org/docs/Classes/ORKTextChoice.html) | valueCoding
| [date](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-date) | [ORKDateAnswerFormat](http://researchkit.org/docs/Classes/ORKDateAnswerFormat.html)(style: [ORKDateAnswerStyle.date](http://researchkit.org/docs/Constants/ORKDateAnswerStyle.html)) | valueDate
| [dateTime](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-dateTime) | [ORKDateAnswerFormat](http://researchkit.org/docs/Classes/ORKDateAnswerFormat.html)(style: [ORKDateAnswerStyle.dateAndTime](http://researchkit.org/docs/Constants/ORKDateAnswerStyle.html)) | valueDateTime
| [decimal](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-decimal) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).decimalAnswerFormat | valueDecimal
| [display](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-display) | [ORKInstructionStep](http://researchkit.org/docs/Classes/ORKInstructionStep.html) | *none*
| [group](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-group) | [ORKFormStep](http://researchkit.org/docs/Classes/ORKFormStep.html) | *none*
| [integer](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-integer) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).integerAnswerFormat | valueInteger
| [quantity](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-quantity) | [ORKNumericAnswerFormat](http://researchkit.org/docs/Classes/ORKNumericAnswerFormat.html).decimalAnswerFormat(withUnit: quantityUnit) | valueQuantity
| [string](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-string) | [ORKTextAnswerFormat](http://researchkit.org/docs/Classes/ORKTextAnswerFormat.html) | valueString
| [text](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-text) | [ORKTextAnswerFormat](http://researchkit.org/docs/Classes/ORKTextAnswerFormat.html) | valueString
| [time](https://www.hl7.org/fhir/codesystem-item-type.html#item-type-time) | [ORKTimeOfDayAnswerFormat](http://researchkit.org/docs/Classes/ORKTimeOfDayAnswerFormat.html) | valueTime


### Navigation Rules

The following table describes how the FHIR [enableWhen](https://www.hl7.org/fhir/questionnaire-definitions.html#Questionnaire.item.enableWhen) is converted to a ResearchKit [ORKSkipStepNavigationRule](http://researchkit.org/docs/Classes/ORKSkipStepNavigationRule.html) for each supported type and operator. (The conversion is performed by constructing an ORKResultPredicate from the enableWhen expression and negating it.)

Multiple enableWhen expressions are supported, using the [enableBehavior](https://www.hl7.org/fhir/questionnaire-definitions.html#Questionnaire.item.enableBehavior) element to determine if any or all of the expressions should be applied. If enableBehavior is not defined, all expressions will be applied.

| FHIR R4 [QuestionnaireItemType](https://www.hl7.org/fhir/valueset-item-type.html) | Supported [QuestionnaireItemOperators](https://www.hl7.org/fhir/valueset-questionnaire-enable-operator.html) | ResearchKit [ORKResultPredicate](http://researchkit.org/docs/Classes/ORKResultPredicate.html) |
| ---------------------------- | ------------------- | ------------------------------ |
| boolean | =, != | .predicateForBooleanQuestionResult
| integer | =, !=, <=, >= | .predicateForNumericQuestionResult
| decimal | =, !=, <=, >= | .predicateForNumericQuestionResult
| date | >, < | .predicateForDateQuestionResult
| coding | =, != | .predicateForChoiceQuestionResult


## Installation

Add the Spezi monorepo package to your app and select the `ResearchKitOnFHIR` product.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ResearchKitOnFHIR", package: "Spezi")
    ]
)
```

## Usage

The `Example` directory contains an Xcode project that demonstrates how to create a ResearchKit task from an FHIR Questionnaire and extract the results in the form of an FHIR QuestionnaireResponse.

### Converting from FHIR to ResearchKit

#### 1. Instantiate an FHIR Questionnaire from JSON

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
    task = try ORKNavigableOrderedTask(questionnaire: questionnaire)
} catch {
    print("Error creating task: \(error)")
}
```

Now you can present the task as described in the [ResearchKit documentation](https://github.com/StanfordBDHG/researchkit#4-present-the-task).

### Converting ResearchKit Task Results to FHIR QuestionnaireResponse

In your class that implements the `ORKTaskViewControllerDelegateProtocol`, you can extract an FHIR [QuestionnaireResponse](https://www.hl7.org/FHIR/questionnaireresponse.html) from the task's results as shown below.

```swift
func taskViewController(
    _ taskViewController: ORKTaskViewController,
    didFinishWith reason: ORKTaskViewControllerFinishReason,
    error: Error?
) {
    switch reason {
    case .completed:
        let fhirResponse = taskViewController.result.fhirResponse
        // ...
    }
}
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.


## Notices

ResearchKit is a registered trademark of Apple, Inc.
FHIR is a registered trademark of Health Level Seven International.
