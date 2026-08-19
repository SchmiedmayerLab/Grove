# ``GroveConsent``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Present your user consent documents to read, sign, and export.

## Overview

GroveConsent implements consent-flow-related infrastructure, providing both a data model (``ConsentDocument``) and views (``ConsentDocumentView``, ``OnboardingConsentView``, etc) for integrating Markdown-based consent documents into your app.

@Row {
    @Column {
        @Image(source: "Consent1", alt: "Screenshot displaying a simple consent form") {
            At its core, a ``ConsentDocument`` is a simple markdown document which the user is asked to sign.
        }
    }
    @Column {
        @Image(source: "Consent2", alt: "Screenshot displaying an interactive consent form") {
            In addition to standard markdown elements, the consent form may also contain custom, interactive toggle or selection components.
        }
    }
    @Column {
        @Image(source: "Consent3", alt: "Screenshot displaying an Interactive Consent Form with selection requirements.") {
            If specified, the consent form will validate the user's selection against an expected value, preventing the user from advancing unless they provide the correct response.
        }
    }
}


Your app uses GroveConsent by creating a ``ConsentDocument`` from a Markdown string or file.
A consent form consists of Markdown content (e.g.: text, headings, lists, etc), and can also contain custom interactive elements which enable support for simple user data collection directly as part of filling out the consent form.
For example, your app could define a consent document consisting of markdown text, followed by a toggle (which the user needs to explicitly set to true in order to confirm their willingness to participate in your study), and a signature field where the user needs to sign their signature.

The ``ConsentDocument`` type handles the state of a (potentially interactive) consent form; it is passed into e.g. a ``ConsentDocumentView`` or an ``OnboardingConsentView``, which present the consent form to a user, allowing them to sign the form and fill out its interactive elements.
Once the user has completed the form, you use the ``ConsentDocument/export(using:)`` function to obtain a PDF representation of the signed document.


### Consent Views

The following example creates a simple, reusable `ConsentStep` view which can be used e.g. as part of your app's onboarding.
The view implements both dynamic consent form loading from a file URL (e.g.: a resource in your app's bundle),
and also provides a share button in the top-right corner, allowing participants to keep a personal copy of the consent form they signed.
```swift
import GroveConsent
import GroveViews
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

Your app would then use this `ConsentStep` when building up its Onboarding Stack:
```swift
import GroveViews

ManagedNavigationStack {
    Welcome()
    EligibilityScreening()
    UserLogin()
    ConsentStep(url: Bundle.main.url(forResource: "consent", withExtension: "md")!)
    HealthPermissions()
    //
}
```

> Note: The [`ManagedNavigationStack`](../../GroveViews/GroveViews.docc/GroveViews.md) in the example above is from the [GroveViews](../../GroveViews/GroveViews.docc/GroveViews.md) package.

### Consent Documents

Below is an example of a simple consent document that embeds several custom elements into its Markdown text:

```html
---
title: Heart Failure Study Consent
version: 1.0.2
---

# Heart Failure Study

Welcome to our Study.

... a bunch of text here ...

Please select your preferences regarding the sharing of your collected, anonymized Health data:

<toggle id=health-permission-internal expected-value=true>
    I'm fine with my anonymized Health data being used for internal research within the organization
</toggle>
<toggle id=health-permission-external>
    I'm fine with my anonymized Health data being used for external research outside the organization
</toggle>

Please sign to confirm your participation:
<signature id=signature />
```


## Topics

### Model
- ``ConsentDocument``
- ``ConsentDocument/ExportConfiguration``
- ``ConsentDocument/ExportResult``
- ``ConsentDocument/ConsentCompletionState``

### Views
- ``ConsentDocumentView``
- ``OnboardingConsentView``
- ``ConsentSignatureForm``
- ``SignatureView``
- ``ConsentShareButton``
