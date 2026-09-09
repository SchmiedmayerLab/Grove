# ``GroveOnboarding``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Provides SwiftUI views for onboarding users onto a digital health application.

## Overview

The `GroveOnboarding` module provides views that can be used for performing onboarding tasks, such as providing an overview of your app and, in combination with [GroveConsent](../../GroveConsent/GroveConsent.docc/GroveConsent.md) asking a user to read and sign consent documents.
Every step is a page of the scaffold in [GroveViews](../../GroveViews/GroveViews.docc/GroveViews.md): a `PageHeader` and content that scroll, and `PageActions` floating over them.

@Row {
    @Column {
        @Image(source: "Welcome", alt: "Screenshot displaying the onboarding view.") {
            An ``OnboardingView`` allows you to separate information into areas on a screen, each with a title, description, and icon, with the actions floating over the content.
        }
    }
    @Column {
        @Image(source: "SequentialSteps", alt: "Screenshot displaying the sequential onboarding view.") {
            A ``SequentialOnboardingView`` allows you to display information step-by-step with each additional area appearing when the user taps the "Next" button.
        }
    }
    @Column {
        @Image(source: "ImageHeader", alt: "Screenshot displaying a permission page with a large tinted symbol above its title.") {
            A `PageHeader` can head a page with a symbol, the way the system's own permission pages do.
        }
    }
    @Column {
        @Image(source: "ScrolledTitle", alt: "Screenshot displaying a long page scrolled down, with its title shown in the navigation bar and the content fading into the actions.") {
            A long page keeps its name: the title moves into the navigation bar once it scrolls away, and the content fades out under the floating actions.
        }
    }
}

Consent documents are read, signed, and exported with the [GroveConsent](../../GroveConsent/GroveConsent.docc/GroveConsent.md) module, whose `OnboardingConsentView` is built on the ``OnboardingView`` and fits into the same flow.



## Setup

### Add Grove Onboarding as a Dependency

You need to add the Grove Onboarding Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).


## Examples

Every step scrolls its header and content, while the actions float over them at the bottom and the content fades into a blur as it runs underneath.
A title can carry an image above it, and it moves up into the navigation bar once it has scrolled out of view.

### Onboarding View

The ``OnboardingView`` allows you to separate information into areas on a screen, each with a title, description, and icon.

```swift
import GroveOnboarding
import SwiftUI


struct OnboardingViewExample: View {
    var body: some View {
        OnboardingView(
            title: "Welcome",
            subtitle: "This is an example onboarding view",
            areas: [
                .init(
                    icon: Image(systemName: "tortoise.fill"),
                    title: "Tortoise",
                    description: "A Tortoise!"
                ),
                .init(
                    icon: {
                        Image(systemName: "lizard.fill")
                            .foregroundColor(.green)
                    },
                    title: "Lizard",
                    description: "A Lizard!"
                ),
                .init(
                    icon: {
                        Circle().fill(.orange)
                    },
                    title: "Circle",
                    description: "A Circle!"
                )
            ],
            actionText: "Learn More",
            action: {
                // Action to perform when the user taps the action button.
            }
        )
    }
}
```


### Sequential Onboarding View

The ``SequentialOnboardingView`` allows you to display information step-by-step, with each additional area appearing when the user taps the `Next` button.

```swift
import GroveOnboarding
import SwiftUI


struct SequentialOnboardingViewExample: View {
    var body: some View {
        SequentialOnboardingView(
            title: "Things to know",
            subtitle: "And you should pay close attention ...",
            steps: [
                .init(
                    title: "A thing to know",
                    description: "This is a first thing that you should know; read carefully!"
                ),
                .init(
                    title: "Second thing to know",
                    description: "This is a second thing that you should know; read carefully!"
                ),
                .init(
                    title: "Third thing to know",
                    description: "This is a third thing that you should know; read carefully!"
                )
            ],
            actionText: "Continue"
        ) {
            // Action to perform when the user has viewed all the steps
        }
    }
}
```



## Topics

### Articles
- <doc:DisplayingInformation>

### Onboarding Views

The page itself, `PageView` with its `PageHeader` and `PageActions`, lives in the Pages topic of
[GroveViews](../../GroveViews/GroveViews.docc/GroveViews.md); this module re-exports it.

- ``OnboardingView``
- ``OnboardingInformationView``
- ``SequentialOnboardingView``
