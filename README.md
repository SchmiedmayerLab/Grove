<!--

This source file is part of the Stanford Spezi open-source project.

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Stanford Spezi

[![CI](https://github.com/SchmiedmayerLab/Spezi/actions/workflows/tests.yml/badge.svg)](.github/workflows/tests.yml)

Open-source framework for the rapid development of modern, interoperable digital health applications.


## Overview

> [!NOTE]
> Refer to the [Initial Setup](Sources/Spezi/Spezi.docc/Initial%20Setup.md) instructions to integrate Spezi into your application.

Spezi introduces a module-based approach to building digital health applications.

<table style="width: 80%">
  <tr>
    <td align="center" width="33.33333%">
      <img src="Sources/SpeziConsent/SpeziConsent.docc/Resources/Consent1.png#gh-light-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
      <img src="Sources/SpeziConsent/SpeziConsent.docc/Resources/Consent1~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="Sources/SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices.png#gh-light-mode-only" alt="Screenshot displaying Spezi Devices and Bluetooth pairing user interface" width="80%"/>
      <img src="Sources/SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices~dark.png#gh-dark-mode-only" alt="Screenshot displaying Spezi Devices and Bluetooth pairing user interface" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="Sources/SpeziQuestionnaire/SpeziQuestionnaire.docc/Resources/Overview.png#gh-light-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
      <img src="Sources/SpeziQuestionnaire/SpeziQuestionnaire.docc/Resources/Overview~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="Sources/SpeziOnboarding/README.md">
        <code>Spezi Onboarding</code>
      </a> and
      <a href="Sources/SpeziConsent/README.md">
        <code>Spezi Consent</code>
      </a>
    </td>
    <td align="center">
      <a href="Sources/SpeziBluetooth/README.md">
        <code>Spezi Bluetooth</code>
      </a> and
      <a href="Sources/SpeziDevices/README.md">
        <code>Spezi Devices</code>
      </a>
    </td>
    <td align="center">
      <a href="Sources/SpeziQuestionnaire/README.md">
        <code>Spezi Questionnaire</code>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="Sources/SpeziAccount/SpeziAccount.docc/Resources/AccountSetup.png#gh-light-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
      <img src="Sources/SpeziAccount/SpeziAccount.docc/Resources/AccountSetup~dark.png#gh-dark-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
    </td>
    <td align="center">
      <img src="Sources/SpeziValidation/SpeziValidation.docc/Resources/Validation.png#gh-light-mode-only" alt="Three different text fields showing validation errors with Spezi Validation" width="80%"/>
      <img src="Sources/SpeziValidation/SpeziValidation.docc/Resources/Validation~dark.png#gh-dark-mode-only" alt="Three different text fields showing validation errors with Spezi Validation" width="80%"/>
    </td>
    <td align="center">
      <img src="Sources/SpeziLLMLocal/SpeziLLMLocal.docc/Resources/ChatView.png#gh-light-mode-only" alt="Chat view of a locally executed LLM using the Spezi LLM module" width="80%"/>
      <img src="Sources/SpeziLLMLocal/SpeziLLMLocal.docc/Resources/ChatView~dark.png#gh-dark-mode-only" alt="Chat view of a locally executed LLM using the Spezi LLM module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="Sources/SpeziAccount/README.md">
        <code>Spezi Account</code>
      </a>
    </td>
    <td align="center">
      <a href="Sources/SpeziViews/README.md">
        <code>Spezi Views</code>
      </a>, including
      <a href="Sources/SpeziValidation/SpeziValidation.docc/SpeziValidation.md">
        <code>SpeziValidation</code>
      </a>
    </td>
    <td align="center">
      <a href="Sources/SpeziLLM/README.md">
        <code>Spezi LLM</code>
      </a>
    </td>
  </tr>
</table>


### An Ecosystem of Modules

You can find the modules and reusable Swift packages included in this monorepo in [Package.swift](Package.swift).

> [!NOTE]
> Spezi relies on an ecosystem of modules. Consider what modules you want to build and contribute to the open-source community. Refer to the [Spezi Guide](Sources/Spezi/Spezi.docc/Spezi%20Guide.md) and [Documentation Guide](Sources/Spezi/Spezi.docc/Documentation%20Guide.md) for requirements for Spezi-based software, and see the [`Module`](Sources/Spezi/Spezi.docc/Module/Module.md) documentation to learn more about building your modules.


## Add Spezi to Your App

This monorepo version of Spezi is distributed as one Swift Package that contains the core Spezi library and several optional Spezi modules.
Add only the products your app needs; for example, most apps start with `Spezi` and then add modules such as `SpeziViews`, `SpeziOnboarding`, `SpeziConsent`, `SpeziAccount`, or `SpeziHealthKit`.

### Xcode

1. Open your app project in Xcode.
2. Select **File > Add Package Dependencies...**.
3. Enter the package URL:

   ```text
   https://github.com/SchmiedmayerLab/Spezi.git
   ```

4. Choose a dependency rule:
   - Choose **Up to Next Minor Version**.
   - Enter the latest tagged `0.x` release.
5. Select the Spezi products your app target needs.
   At minimum, select `Spezi`.
   Add additional products only when you use them, such as `SpeziViews`, `SpeziOnboarding`, `SpeziConsent`, `SpeziAccount`, or `SpeziHealthKit`.
6. Make sure the products are added to your app target, not only to a test target.
7. Import the modules in Swift files where you use them:

   ```swift
   import Spezi
   import SpeziViews
   ```

### Swift Package Manager

If your app or library already has a `Package.swift`, add this package to the `dependencies` section.
For a complete Spezi setup, enable all optional package traits:

```swift
.package(
    url: "https://github.com/SchmiedmayerLab/Spezi.git",
    "0.1.0"..<"0.2.0",
    traits: ["Textual", "MLX", "ResearchKit"]
)
```

Then add the products you use to the target that needs them:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Spezi", package: "Spezi"),
        .product(name: "SpeziViews", package: "Spezi"),
        .product(name: "SpeziOnboarding", package: "Spezi")
    ]
)
```

Use an Xcode or Swift toolchain that supports Swift Package tools version 6.2.
If Xcode cannot resolve the package, confirm that the package URL and selected version are correct, then use **File > Packages > Resolve Package Versions**.


### Package Traits and Deployment Targets

Spezi is developed for the current and previous Apple platform generations: currently Apple 26 and the iOS 18 generation (iOS 18, macOS 15, watchOS 11, tvOS 18, and visionOS 2).
For the complete Spezi feature set, enable all optional package traits.
If your app needs older deployment targets, disable optional traits and guard newer APIs with availability checks.
The lower compile-compatibility floor is the 2021 Apple platform generation declared by the package manifest: iOS 15, macOS 12, and watchOS 8.

| Deployment target | Recommended traits | Relevant targets |
| --- | --- | --- |
| Apple 26 and iOS 18 generation | `["Textual", "MLX", "ResearchKit"]` | Complete Spezi feature set. |
| iOS 17 generation (iOS 17, macOS 14, watchOS 10, tvOS 17, visionOS 1) | `["MLX", "ResearchKit"]` where needed | `MLX` for `SpeziLLMLocal` and `SpeziLLMLocalDownload`; `ResearchKit` for `ResearchKitOnFHIR` and `SpeziQuestionnaireLegacy` on iOS. |
| iOS 16 and iOS 15 generations | `[]` | Core products; use availability checks around newer APIs. |

```swift
.package(
    url: "https://github.com/SchmiedmayerLab/Spezi.git",
    "0.1.0"..<"0.2.0",
    traits: []
)
```


### The Spezi Building Blocks

> [!NOTE]
> The [Spezi Guide](Sources/Spezi/Spezi.docc/Spezi%20Guide.md) and [Documentation Guide](Sources/Spezi/Spezi.docc/Documentation%20Guide.md) outline the requirements for Spezi-based modules, including terminology, guidance, and examples on structuring a Spezi module, Swift package, and repository.

A ``Standard`` defines the key coordinator that orchestrates data flow in an application by meeting requirements defined by modules.
You can learn more about the ``Standard`` protocol and when it is advised to create your own standard in the [`Standard`](Sources/Spezi/Spezi.docc/Standard.md) documentation.

A ``Module`` defines a software subsystem that provides distinct and reusable functionality.
Modules can use the constraint mechanism to enforce a set of requirements for the standard used in Spezi-based software.
They can also define dependencies on each other to reuse functionality and can communicate with other modules by offering and collecting information.
Modules may conform to different protocols to access additional Spezi features, such as lifecycle management and triggering view updates in SwiftUI using Swift’s observable mechanisms.
You can learn more about modules in the [`Module`](Sources/Spezi/Spezi.docc/Module/Module.md) documentation.


For more information, see the [Spezi documentation catalog](Sources/Spezi/Spezi.docc/Spezi.md).


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](Sources/Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

The original Spezi and BDHG projects may continue to be maintained in their respective upstream repositories under the [StanfordSpezi](https://github.com/StanfordSpezi) and [StanfordBDHG](https://github.com/StanfordBDHG) GitHub organizations. Please refer to the upstream repositories for their current development status and new releases.


## License

This project is licensed under the MIT License. See [Licenses](LICENSES) for more information.

This repository is based on the [`StanfordSpezi/Spezi` repository](https://github.com/StanfordSpezi/Spezi) and incorporates content from several [`StanfordSpezi` repositories](https://github.com/StanfordSpezi) and [`StanfordBDHG` repositories](https://github.com/StanfordBDHG), all of which were published under the MIT License.

Please refer to the individual repositories for detailed and updated contributor lists, including the [`StanfordSpezi/Spezi` contributors file](https://github.com/StanfordSpezi/Spezi/blob/main/CONTRIBUTORS.md).


## Our Research

For more information, visit the [Schmiedmayer Lab GitHub organization](https://github.com/SchmiedmayerLab).

![Stanford and Stanford Medicine logos](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/stanford-footer-light.png#gh-light-mode-only)
![Stanford and Stanford Medicine logos](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/stanford-footer-dark.png#gh-dark-mode-only)
