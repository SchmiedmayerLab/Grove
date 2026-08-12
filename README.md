<!--

This source file is part of the Grove open-source project.

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Stanford Grove

[![Build and Test](https://github.com/SchmiedmayerLab/Grove/actions/workflows/tests.yml/badge.svg)](https://github.com/SchmiedmayerLab/Grove/actions/workflows/tests.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/SchmiedmayerLab/Grove)](https://api.reuse.software/info/github.com/SchmiedmayerLab/Grove)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Open-source framework for the rapid development of modern, interoperable digital health applications.


## Overview

> [!NOTE]
> Refer to the [Initial Setup](Sources/Grove/Grove.docc/Initial-Setup.md) instructions to integrate Grove into your application.

Grove introduces a module-based approach to building digital health applications.

<table style="width: 80%">
  <tr>
    <td align="center" width="33.33333%">
      <img src="Sources/GroveConsent/GroveConsent.docc/Resources/Consent1.png#gh-light-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
      <img src="Sources/GroveConsent/GroveConsent.docc/Resources/Consent1~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="Sources/GroveDevicesUI/GroveDevicesUI.docc/Resources/PairedDevices.png#gh-light-mode-only" alt="Screenshot displaying Grove Devices and Bluetooth pairing user interface" width="80%"/>
      <img src="Sources/GroveDevicesUI/GroveDevicesUI.docc/Resources/PairedDevices~dark.png#gh-dark-mode-only" alt="Screenshot displaying Grove Devices and Bluetooth pairing user interface" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="Sources/GroveQuestionnaire/GroveQuestionnaire.docc/Resources/Overview.png#gh-light-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
      <img src="Sources/GroveQuestionnaire/GroveQuestionnaire.docc/Resources/Overview~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/groveonboarding">
        <code>Grove Onboarding</code>
      </a> and
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/groveconsent">
        <code>Grove Consent</code>
      </a>
    </td>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/grovebluetooth">
        <code>Grove Bluetooth</code>
      </a> and
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/grovedevices">
        <code>Grove Devices</code>
      </a>
    </td>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/grovequestionnaire">
        <code>Grove Questionnaire</code>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="Sources/GroveAccount/GroveAccount.docc/Resources/AccountSetup.png#gh-light-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
      <img src="Sources/GroveAccount/GroveAccount.docc/Resources/AccountSetup~dark.png#gh-dark-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
    </td>
    <td align="center">
      <img src="Sources/GroveValidation/GroveValidation.docc/Resources/Validation.png#gh-light-mode-only" alt="Three different text fields showing validation errors with Grove Validation" width="80%"/>
      <img src="Sources/GroveValidation/GroveValidation.docc/Resources/Validation~dark.png#gh-dark-mode-only" alt="Three different text fields showing validation errors with Grove Validation" width="80%"/>
    </td>
    <td align="center">
      <img src="Sources/GroveLLMLocal/GroveLLMLocal.docc/Resources/ChatView.png#gh-light-mode-only" alt="Chat view of a locally executed LLM using the Grove LLM module" width="80%"/>
      <img src="Sources/GroveLLMLocal/GroveLLMLocal.docc/Resources/ChatView~dark.png#gh-dark-mode-only" alt="Chat view of a locally executed LLM using the Grove LLM module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/groveaccount">
        <code>Grove Account</code>
      </a>
    </td>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/groveviews">
        <code>Grove Views</code>
      </a>, including
      <a href="Sources/GroveValidation/GroveValidation.docc/GroveValidation.md">
        <code>GroveValidation</code>
      </a>
    </td>
    <td align="center">
      <a href="https://swiftpackageindex.com/SchmiedmayerLab/Grove/documentation/grovellm">
        <code>Grove LLM</code>
      </a>
    </td>
  </tr>
</table>


### An Ecosystem of Modules

You can find the modules and reusable Swift packages included in this monorepo in [Package.swift](Package.swift).

> [!NOTE]
> Grove relies on an ecosystem of modules. Consider what modules you want to build and contribute to the open-source community. Refer to the [Grove Guide](Sources/Grove/Grove.docc/Grove-Guide.md) and [Documentation Guide](Sources/Grove/Grove.docc/Documentation-Guide.md) for requirements for Grove-based software, and see the [`Module`](Sources/Grove/Grove.docc/Module/Module.md) documentation to learn more about building your modules.


## Add Grove to Your App

This monorepo version of Grove is distributed as one Swift Package that contains the core Grove library and several optional Grove modules.
Add only the products your app needs; for example, most apps start with `Grove` and then add modules such as `GroveViews`, `GroveOnboarding`, `GroveConsent`, `GroveAccount`, or `GroveHealthKit`.

### Xcode

1. Open your app project in Xcode.
2. Select **File > Add Package Dependencies...**.
3. Enter the package URL:

   ```text
   https://github.com/SchmiedmayerLab/Grove.git
   ```

4. Choose a dependency rule:
   - Choose **Up to Next Minor Version**.
   - Enter the latest tagged `0.x` release.
5. Select the Grove products your app target needs.
   At minimum, select `Grove`.
   Add additional products only when you use them, such as `GroveViews`, `GroveOnboarding`, `GroveConsent`, `GroveAccount`, or `GroveHealthKit`.
6. Make sure the products are added to your app target, not only to a test target.
7. Import the modules in Swift files where you use them:

   ```swift
   import Grove
   import GroveViews
   ```

### Swift Package Manager

If your app or library already has a `Package.swift`, add this package to the `dependencies` section:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Grove.git", .upToNextMinor(from: "0.3.0"))
```

Then add the products you use to the target that needs them:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Grove", package: "Grove"),
        .product(name: "GroveViews", package: "Grove"),
        .product(name: "GroveOnboarding", package: "Grove")
    ]
)
```

Use an Xcode or Swift toolchain that supports Swift Package tools version 6.2.
If Xcode cannot resolve the package, confirm that the package URL and selected version are correct, then use **File > Packages > Resolve Package Versions**.


### The Grove Building Blocks

> [!NOTE]
> The [Grove Guide](Sources/Grove/Grove.docc/Grove-Guide.md) and [Documentation Guide](Sources/Grove/Grove.docc/Documentation-Guide.md) outline the requirements for Grove-based modules, including terminology, guidance, and examples on structuring a Grove module, Swift package, and repository.

A ``Standard`` defines the key coordinator that orchestrates data flow in an application by meeting requirements defined by modules.
You can learn more about the ``Standard`` protocol and when it is advised to create your own standard in the [`Standard`](Sources/Grove/Grove.docc/Standard.md) documentation.

A ``Module`` defines a software subsystem that provides distinct and reusable functionality.
Modules can use the constraint mechanism to enforce a set of requirements for the standard used in Grove-based software.
They can also define dependencies on each other to reuse functionality and can communicate with other modules by offering and collecting information.
Modules may conform to different protocols to access additional Grove features, such as lifecycle management and triggering view updates in SwiftUI using Swift’s observable mechanisms.
You can learn more about modules in the [`Module`](Sources/Grove/Grove.docc/Module/Module.md) documentation.


For more information, see the [Grove documentation catalog](Sources/Grove/Grove.docc/Grove.md).

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](Sources/Grove/Grove.docc/Contributing-Guide.md), the [contribution guidelines](https://github.com/SchmiedmayerLab/.github/blob/main/CONTRIBUTING.md) and the [contributor covenant code of conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first. You can find a list of contributors in the [CONTRIBUTORS.md](CONTRIBUTORS.md) file.

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for more information.

## Citation

If you use this software, please cite it using the metadata in [CITATION.cff](CITATION.cff), which GitHub surfaces through the [*Cite this repository*](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-citation-files) button.

## Our Research

For more information, visit the [Schmiedmayer Lab GitHub organization](https://github.com/SchmiedmayerLab).

![Schmiedmayer Lab](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/footer-light.png#gh-light-mode-only)
![Schmiedmayer Lab](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/footer-dark.png#gh-dark-mode-only)
