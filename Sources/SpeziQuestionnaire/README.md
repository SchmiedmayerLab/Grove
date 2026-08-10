<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Questionnaire


Enables apps to display and collect responses from [HL7® FHIR® questionnaires](http://hl7.org/fhir/R4/questionnaire.html).


## Overview

The Spezi Questionnaire package enables [HL7® FHIR® Questionnaires](http://hl7.org/fhir/R4/questionnaire.html) to be displayed in your Spezi application.

Questionnaires are displayed using [ResearchKit](https://github.com/ResearchKit/ResearchKit) and the [ResearchKitOnFHIR](../ResearchKitOnFHIR/README.md) package.

| ![Screenshot showing a Questionnaire rendered using the Spezi Questionnaire module.](SpeziQuestionnaire.docc/Resources/Overview.png#gh-light-mode-only) ![Screenshot showing a Questionnaire rendered using the Spezi Questionnaire module.](SpeziQuestionnaire.docc/Resources/Overview~dark.png#gh-dark-mode-only) |
 |:---:|
 |An HL7® FHIR® Questionnaire is rendered using the `QuestionnaireView`|


## Setup

Add the Spezi monorepo package to your app and select the products you need, such as `SpeziQuestionnaire`, `SpeziQuestionnaireCatalog`, or `SpeziQuestionnaireFHIR`.

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
        .product(name: "SpeziQuestionnaire", package: "Spezi"),
        .product(name: "SpeziQuestionnaireCatalog", package: "Spezi"),
        .product(name: "SpeziQuestionnaireFHIR", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

## Example

In the following example, we create a SwiftUI view with a button that displays a sample questionnaire from the `FHIRQuestionnaires` package using `QuestionnaireView`.

```swift
import FHIRQuestionnaires
import SpeziQuestionnaire
import SwiftUI


struct ExampleQuestionnaireView: View {
    @State var displayQuestionnaire = false


    var body: some View {
        Button("Display Questionnaire") {
            displayQuestionnaire.toggle()
        }
            .sheet(isPresented: $displayQuestionnaire) {
                QuestionnaireView(
                    questionnaire: Questionnaire.gcs
                ) { result in
                    guard case let .completed(response) = result else {
                        return // user cancelled
                    }

                    // ... save the FHIR response to your data store
                }
            }
    }
}
```
For more information, please refer to the [SpeziQuestionnaire](SpeziQuestionnaire.docc/SpeziQuestionnaire.md) and [SpeziQuestionnaireFHIR](../SpeziQuestionnaireFHIR/SpeziQuestionnaireFHIR.docc/SpeziQuestionnaireFHIR.md) documentation.


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the Spezi Questionnaire module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## Notices

FHIR is a registered trademark of Health Level Seven International.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
