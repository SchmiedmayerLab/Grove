# Displaying Information

<!--
                  
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

Display information to your user during an onboarding flow.

## OnboardingView

The ``OnboardingView`` allows you to separate information into areas on a screen, each with a title, description, and icon.
It is a `PageView` from [GroveViews](../../GroveViews/GroveViews.docc/GroveViews.md): a `PageHeader` and an
``OnboardingInformationView`` that scroll, with `PageActions` floating over them as the content fades out beneath.

@Image(source: "Welcome")

The following example demonstrates how the above view is constructed:

```swift
OnboardingView {
    PageHeader(
        title: "Heart Health Study",
        subtitle: "How everyday activity shapes a healthy heart."
    )
} content: {
    OnboardingInformationView {
        OnboardingInformationView.Area(
            iconSymbol: "applewatch",
            title: "Wear Your Watch",
            description: "Heart rate and activity are recorded the way they already are; nothing extra to do."
        )
        OnboardingInformationView.Area(
            iconSymbol: "list.clipboard",
            title: "Weekly Check-Ins",
            description: "A short questionnaire once a week asks how you have been feeling and what your days were like."
        )
        OnboardingInformationView.Area(
            iconSymbol: "lock.shield",
            title: "Your Data Stays Yours",
            description: "Everything stays on your device until you choose to share it with the study team."
        )
        OnboardingInformationView.Area(
            iconSymbol: "chart.line.uptrend.xyaxis",
            title: "See What Changes",
            description: "Your own trends are shown back to you as the weeks go by, alongside what the study learns."
        )
    }
} footer: {
    PageActions(
        primaryTitle: "Learn More",
        primaryAction: {
            // Action to perform when the user taps the primary button.
        },
        secondaryTitle: "Also Learn More",
        secondaryAction: {
            // Action to perform when the user taps the secondary button.
        }
    )
}
```

A `PageHeader` can also carry an image above the title, drawn large and tinted, the way a symbol heads a permission page:

@Image(source: "ImageHeader")

```swift
PageHeader(
    title: "Health Access",
    subtitle: "Your Health data stays on your device unless you decide otherwise.",
    image: Image(systemName: "heart.text.square")
)
```

## SequentialOnboardingView

The ``SequentialOnboardingView`` allows you to display information step-by-step, with each additional area appearing when the user taps the `Next` button.

@Image(source: "SequentialSteps")

The following example demonstrates how the above view is constructed:

```swift
SequentialOnboardingView(
    title: "What to Expect",
    subtitle: "Four steps, and the study begins.",
    steps: [
        .init(
            title: "Consent",
            description: "Read what taking part means and sign on the next page."
        ),
        .init(
            title: "Health Access",
            description: "Allow the app to read heart rate and activity from Apple Health."
        ),
        .init(
            title: "First Check-In",
            description: "Answer the first weekly questionnaire; it takes about two minutes."
        ),
        .init(
            title: "Reminders",
            description: "Choose the evening you would like to be reminded each week."
        )
    ],
    actionText: "Continue"
) {
    // Action to perform when the user has viewed all the steps
}
```

## Topics

### Views

- ``OnboardingView``
- ``OnboardingInformationView``
- ``SequentialOnboardingView``
