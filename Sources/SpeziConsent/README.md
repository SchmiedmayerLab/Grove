<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziConsent


Provides UI components for consent handling in your app.


## Overview

The SpeziConsent module provides utilities for retrieving consent for e.g. study participation.


<table style="width: 80%">
  <tr>
    <td align="center" width="33.33333%">
      <img src="SpeziConsent.docc/Resources/Consent1.png#gh-light-mode-only" alt="Screenshot displaying a simple consent form" width="80%"/>
      <img src="SpeziConsent.docc/Resources/Consent1~dark.png#gh-dark-mode-only" alt="Screenshot displaying a simple consent form" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="SpeziConsent.docc/Resources/Consent2.png#gh-light-mode-only" alt="Screenshot displaying an interactive consent form" width="80%"/>
      <img src="SpeziConsent.docc/Resources/Consent2~dark.png#gh-dark-mode-only" alt="Screenshot displaying an interactive consent form" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="SpeziConsent.docc/Resources/Consent3.png#gh-light-mode-only" alt="Screenshot displaying an interactive consent form with required responses" width="80%"/>
      <img src="SpeziConsent.docc/Resources/Consent3~dark.png#gh-dark-mode-only" alt="Screenshot displaying an interactive consent form with required responses" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      Simple Consent Form
    </td>
    <td align="center">
      Interactive Consent Form
    </td>
    <td align="center">
      Interactive Consent Form with Selection Requirements
    </td>
  </tr>
</table>


### Onboarding Consent View

The `OnboardingConsentView` can be used to allow your users to read and agree to a document, e.g., a consent document for a research study or a terms and conditions document for an app. The document can be signed using a family and given name and a hand-drawn signature. The signed consent form can then be exported and shared as a PDF file.

The following example demonstrates how the `OnboardingConsentView` shown above is constructed by reading a consent form from a markdown file, creating a `ConsentDocument` and passing it to the `OnboardingConsentView`, and  an action that should be performed once the consent has been given (which receives the exported consent form as a PDF), as well as a configuration defining the properties of the exported consent form.

The following example demonstrates using the  `OnboardingConsentView` to present a consent form to the user as part of an onboarding flow.
Once the consent if completed (i.e., the user signed it and filled out all required form elements), the user can continue to the next onboarding step.
The view also uses the `ConsentShareButton` to allow the user to obtain a PDF-exported copy of their signed consent document.

```swift
import SpeziConsent
import SpeziViews
import SwiftUI

struct ConsentStep: View {
    let url: URL

    @State private var consentDocument: ConsentDocument?
    @State private var viewState: ViewState = .idle

    var body: some View {
        OnboardingConsentView(consentDocument: consentDocument, viewState: $viewState) {
            // advance your Onboarding flow in response to the user having confirmed a completed consent document
        }
        .viewStateAlert(state: $viewState)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // give your user the ability to obtain a PDF version of the consent document they just signed
                ConsentShareButton(
                    consentDocument: consentDocument,
                    viewState: $viewState
                )
            }
        }
        .task {
            // load the consent document when the view is first displayed.
            // this will automatically cause the `OnboardingConsentView` above to update its contents.
            do {
                consentDocument = try ConsentDocument(contentsOf: url)
            } catch {
                viewState = .error(AnyLocalizedError(error: error))
            }
        }
    }
}
```

For more information, please refer to the [API documentation](SpeziConsent.docc/SpeziConsent.md).


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziConsent` module.



## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
