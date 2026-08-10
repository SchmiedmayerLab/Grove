<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Stanford Spezi


Open-source framework for the rapid development of modern, interoperable digital health applications.


## Overview

> [!NOTE]
> Refer to the [Initial Setup](Spezi.docc/Initial%20Setup.md) instructions to integrate Spezi into your application.

Spezi introduces a module-based approach to building digital health applications.

<table style="width: 80%">
  <tr>
    <td align="center" width="33.33333%">
      <img src="../SpeziConsent/SpeziConsent.docc/Resources/Consent1.png#gh-light-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
      <img src="../SpeziConsent/SpeziConsent.docc/Resources/Consent1~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the consent module" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices.png#gh-light-mode-only" alt="Screenshot displaying Spezi Devices and Bluetooth pairing user interface" width="80%"/>
      <img src="../SpeziDevicesUI/SpeziDevicesUI.docc/Resources/PairedDevices~dark.png#gh-dark-mode-only" alt="Screenshot displaying Spezi Devices and Bluetooth pairing user interface" width="80%"/>
    </td>
    <td align="center" width="33.33333%">
      <img src="../SpeziQuestionnaire/SpeziQuestionnaire.docc/Resources/Overview.png#gh-light-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
      <img src="../SpeziQuestionnaire/SpeziQuestionnaire.docc/Resources/Overview~dark.png#gh-dark-mode-only" alt="Screenshot displaying the UI of the questionnaire module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="../SpeziOnboarding/README.md">
        <code>Spezi Onboarding</code>
      </a> and
      <a href="../SpeziConsent/README.md">
        <code>Spezi Consent</code>
      </a>
    </td>
    <td align="center">
      <a href="../SpeziBluetooth/README.md">
        <code>Spezi Bluetooth</code>
      </a> and
      <a href="../SpeziDevices/README.md">
        <code>Spezi Devices</code>
      </a>
    </td>
    <td align="center">
      <a href="../SpeziQuestionnaire/README.md">
        <code>Spezi Questionnaire</code>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="../SpeziAccount/SpeziAccount.docc/Resources/AccountSetup.png#gh-light-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
      <img src="../SpeziAccount/SpeziAccount.docc/Resources/AccountSetup~dark.png#gh-dark-mode-only" alt="Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button" width="80%"/>
    </td>
    <td align="center">
      <img src="../SpeziValidation/SpeziValidation.docc/Resources/Validation.png#gh-light-mode-only" alt="Three different text fields showing validation errors with Spezi Validation" width="80%"/>
      <img src="../SpeziValidation/SpeziValidation.docc/Resources/Validation~dark.png#gh-dark-mode-only" alt="Three different text fields showing validation errors with Spezi Validation" width="80%"/>
    </td>
    <td align="center">
      <img src="../SpeziLLMLocal/SpeziLLMLocal.docc/Resources/ChatView.png#gh-light-mode-only" alt="Chat view of a locally executed LLM using the Spezi LLM module" width="80%"/>
      <img src="../SpeziLLMLocal/SpeziLLMLocal.docc/Resources/ChatView~dark.png#gh-dark-mode-only" alt="Chat view of a locally executed LLM using the Spezi LLM module" width="80%"/>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="../SpeziAccount/README.md">
        <code>Spezi Account</code>
      </a>
    </td>
    <td align="center">
      <a href="../SpeziViews/README.md">
        <code>Spezi Views</code>
      </a>, including
      <a href="../SpeziValidation/SpeziValidation.docc/SpeziValidation.md">
        <code>SpeziValidation</code>
      </a>
    </td>
    <td align="center">
      <a href="../SpeziLLM/README.md">
        <code>Spezi LLM</code>
      </a>
    </td>
  </tr>
</table>


### An Ecosystem of Modules

You can find the modules and reusable Swift packages included in this monorepo in [Package.swift](../../Package.swift).

> [!NOTE]
> Spezi relies on an ecosystem of modules. Consider what modules you want to build and contribute to the open-source community. Refer to the [Spezi Guide](Spezi.docc/Spezi%20Guide.md) and [Documentation Guide](Spezi.docc/Documentation%20Guide.md) for requirements for Spezi-based software, and see the [`Module`](Spezi.docc/Module/Module.md) documentation to learn more about building your modules.


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

If your app or library already has a `Package.swift`, add this package to the `dependencies` section:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
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


### The Spezi Building Blocks

> [!NOTE]
> The [Spezi Guide](Spezi.docc/Spezi%20Guide.md) and [Documentation Guide](Spezi.docc/Documentation%20Guide.md) outline the requirements for Spezi-based modules, including terminology, guidance, and examples on structuring a Spezi module, Swift package, and repository.

A ``Standard`` defines the key coordinator that orchestrates data flow in an application by meeting requirements defined by modules.
You can learn more about the ``Standard`` protocol and when it is advised to create your own standard in the [`Standard`](Spezi.docc/Standard.md) documentation.

A ``Module`` defines a software subsystem that provides distinct and reusable functionality.
Modules can use the constraint mechanism to enforce a set of requirements for the standard used in Spezi-based software.
They can also define dependencies on each other to reuse functionality and can communicate with other modules by offering and collecting information.
Modules may conform to different protocols to access additional Spezi features, such as lifecycle management and triggering view updates in SwiftUI using Swift’s observable mechanisms.
You can learn more about modules in the [`Module`](Spezi.docc/Module/Module.md) documentation.


For more information, see the [Spezi documentation catalog](Spezi.docc/Spezi.md).


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

The original Spezi and BDHG projects may continue to be maintained in their respective upstream repositories under the [StanfordSpezi](https://github.com/StanfordSpezi) and [StanfordBDHG](https://github.com/StanfordBDHG) GitHub organizations. Please refer to the upstream repositories for their current development status and new releases.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
