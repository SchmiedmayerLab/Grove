# ``Spezi``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Open-source framework for the rapid development of modern, interoperable digital health applications.

## Overview

> Tip: Refer to the <doc:Initial-Setup> instructions to integrate Spezi into your application.

Spezi introduces a module-based approach to building digital health applications.

<!--
Unfortunately, DocC currently does not support dark mode images: https://github.com/apple/swift-docc/pull/359#issuecomment-1214405608
-->
@Row {
    @Column {
        @Image(source: "Consent1", alt: "Screenshot displaying the UI of the consent module.") {
            The [Spezi Onboarding](../../SpeziOnboarding/SpeziOnboarding.docc/SpeziOnboarding.md) and [Spezi Consent](../../SpeziConsent/SpeziConsent.docc/SpeziConsent.md) modules.
        }
    }
    @Column {
        @Image(source: "PairedDevices", alt: "Screenshot displaying Spezi Devices and Bluetooth pairing user interface.") {
            The [Spezi Bluetooth](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) and [Spezi Devices](../../SpeziDevices/SpeziDevices.docc/SpeziDevices.md) modules.
        }
    }
    @Column {
        @Image(source: "QuestionnaireOverview", alt: "Screenshot displaying the UI of the questionnaire module.") {
            The [Spezi Questionnaire](../../SpeziQuestionnaire/SpeziQuestionnaire.docc/SpeziQuestionnaire.md) module.
        }
    }
}
@Row {
    @Column {
        @Image(source: "AccountSetup", alt: "Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button using the Spezi Account module.") {
            The [Spezi Account](../../SpeziAccount/SpeziAccount.docc/SpeziAccount.md) module.
        }
    }
    @Column {
        @Image(source: "Validation", alt: "Three different text fields showing validation errors with the Spezi Validation package.") {
            The [Spezi Views](../../SpeziViews/SpeziViews.docc/SpeziViews.md) module, including the [SpeziValidation](../../SpeziValidation/SpeziValidation.docc/SpeziValidation.md) target.
        }
    }
    @Column {
        @Image(source: "ChatView", alt: "Chat view of a locally executed LLM using the Spezi LLM module.") {
            The [Spezi LLM](../../SpeziLLM/SpeziLLM.docc/SpeziLLM.md) module.
        }
    }
}

### An Ecosystem of Modules

You can find a list of modules and reusable Swift packages offered by the Spezi team at Stanford on the Spezi monorepo package manifest.

> Note: Spezi relies on an ecosystem of modules. Consider what modules you want to build and contribute to the open-source community. Refer to the <doc:Spezi-Guide> and <doc:Documentation-Guide> for requirements for Spezi-based software modules, and see the ``Module`` documentation to learn more about building your modules.

> Tip: You can find a complete list of the Swift-based Spezi modules on the Spezi monorepo page.

### The Spezi Building Blocks

> Tip: The <doc:Spezi-Guide> and <doc:Documentation-Guide> guides outline the requirements for Spezi-based modules, including terminology, guidance, and examples on structuring your Spezi module, Swift package, and repository.

A ``Standard`` defines the key coordinator that orchestrates data flow in an application by meeting requirements defined by modules.
You can learn more about the ``Standard`` protocol and when it is advised to create your own standard in your application in the <doc:Standard> documentation.

A ``Module`` defines a software subsystem providing distinct and reusable functionality.
Modules can use the constraint mechanism to enforce a set of requirements for the standard used in the Spezi-based software where the module is used.
Modules also define dependencies on each other to reuse functionality and can communicate with other modules by offering and collecting information.
You can learn more about modules in the <doc:Module> documentation.

## Topics

### Configuration

- <doc:Initial-Setup>
- ``SpeziAppDelegate``
- ``Configuration``
- ``SwiftUICore/View/spezi(_:)-3bn89``

### Essential Concepts

- ``Spezi/Spezi``
- ``Standard``
- ``Module``

### Previews

- ``SwiftUICore/View/previewWith(standard:simulateLifecycle:_:)``
- ``SwiftUICore/View/previewWith(simulateLifecycle:_:)``
- ``Foundation/ProcessInfo/isPreviewSimulator``
- ``LifecycleSimulationOptions``

### Contribute to Spezi

- <doc:Contributing-Guide>
- <doc:Spezi-Guide>
- <doc:Documentation-Guide>
