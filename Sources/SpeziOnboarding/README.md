<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Onboarding


Provides UI components for Onboarding.


## Overview

The [`SpeziOnboarding`](SpeziOnboarding.docc/SpeziOnboarding.md) module provides user interface components to onboard a user to an iOS application.

<table style="width: 80%">
  <tr>
    <td align="center" width="33.33333%">
      <img src="SpeziOnboarding.docc/Resources/OnboardingView.png#gh-light-mode-only" alt="Screenshot displaying the onboarding view" width="80%"/>
      <img src="SpeziOnboarding.docc/Resources/OnboardingView~dark.png#gh-dark-mode-only" alt="Screenshot displaying the onboarding view" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="SpeziOnboarding.docc/Resources/SequentialOnboarding.png#gh-light-mode-only" alt="Screenshot displaying the sequential onboarding view" width="80%"/>
      <img src="SpeziOnboarding.docc/Resources/SequentialOnboarding~dark.png#gh-dark-mode-only" alt="Screenshot displaying the sequential onboarding view" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="SpeziOnboarding.docc/Resources/Consent.png#gh-light-mode-only" alt="Screenshot displaying the onboarding view" width="80%"/>
      <img src="SpeziOnboarding.docc/Resources/Consent~dark.png#gh-dark-mode-only" alt="Screenshot displaying the onboarding view" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
        <a href="SpeziOnboarding.docc/SpeziOnboarding.md"><code>OnboardingView</code></a>
    </td>
    <td align="center">
        <a href="SpeziOnboarding.docc/SpeziOnboarding.md"><code>SequentialOnboardingView</code></a>
    </td>
    <td align="center">
        <a href="../SpeziConsent/SpeziConsent.docc/SpeziConsent.md"><code>OnboardingConsentView</code></a>
    </td>
  </tr>
</table>


## Setup

### Add Spezi Onboarding as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziOnboarding` product.

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
        .product(name: "SpeziOnboarding", package: "Spezi")
    ]
)
```


## Examples

### Onboarding View

The `OnboardingView` is described in the [SpeziOnboarding documentation](SpeziOnboarding.docc/SpeziOnboarding.md) and allows you to separate information into areas on a screen, each with a title, description, and icon.

```swift
import SpeziOnboarding
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

The `SequentialOnboardingView` is described in the [SpeziOnboarding documentation](SpeziOnboarding.docc/SpeziOnboarding.md) and allows you to display information step-by-step with each additional area appearing when the user taps the `Continue` button.

```swift
import SpeziOnboarding
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


## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziOnboarding` module.



## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
