# ``Grove``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Open-source framework for the rapid development of modern, interoperable digital health applications.

## Overview

> Tip: Refer to the <doc:Initial-Setup> instructions to integrate Grove into your application.

Grove introduces a module-based approach to building digital health applications.

<!--
Unfortunately, DocC currently does not support dark mode images: https://github.com/apple/swift-docc/pull/359#issuecomment-1214405608
-->
@Row {
    @Column {
        @Image(source: "Consent1", alt: "Screenshot displaying the UI of the consent module.") {
            The [Grove Onboarding](../../GroveOnboarding/GroveOnboarding.docc/GroveOnboarding.md) and [Grove Consent](../../GroveConsent/GroveConsent.docc/GroveConsent.md) modules.
        }
    }
    @Column {
        @Image(source: "PairedDevices", alt: "Screenshot displaying Grove Devices and Bluetooth pairing user interface.") {
            The [Grove Bluetooth](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) and [Grove Devices](../../GroveDevices/GroveDevices.docc/GroveDevices.md) modules.
        }
    }
    @Column {
        @Image(source: "QuestionnaireOverview", alt: "Screenshot displaying the UI of the questionnaire module.") {
            The [Grove Questionnaire](../../GroveQuestionnaire/GroveQuestionnaire.docc/GroveQuestionnaire.md) module.
        }
    }
}
@Row {
    @Column {
        @Image(source: "AccountSetup", alt: "Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button using the Grove Account module.") {
            The [Grove Account](../../GroveAccount/GroveAccount.docc/GroveAccount.md) module.
        }
    }
    @Column {
        @Image(source: "Validation", alt: "Three different text fields showing validation errors with the Grove Validation package.") {
            The [Grove Views](../../GroveViews/GroveViews.docc/GroveViews.md) module, including the [GroveValidation](../../GroveValidation/GroveValidation.docc/GroveValidation.md) target.
        }
    }
    @Column {
        @Image(source: "ChatView", alt: "Chat view of a locally executed LLM using the Grove LLM module.") {
            The [Grove LLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) module.
        }
    }
}

### An Ecosystem of Modules

You can find a list of modules and reusable Swift packages offered by the Grove team at Stanford on the Grove monorepo package manifest.

> Note: Grove relies on an ecosystem of modules. Consider what modules you want to build and contribute to the open-source community. Refer to the <doc:Grove-Guide> and <doc:Documentation-Guide> for requirements for Grove-based software modules, and see the ``Module`` documentation to learn more about building your modules.

> Tip: You can find a complete list of the Swift-based Grove modules on the Grove monorepo page.

### The Grove Building Blocks

> Tip: The <doc:Grove-Guide> and <doc:Documentation-Guide> guides outline the requirements for Grove-based modules, including terminology, guidance, and examples on structuring your Grove module, Swift package, and repository.

A ``Standard`` defines the key coordinator that orchestrates data flow in an application by meeting requirements defined by modules.
You can learn more about the ``Standard`` protocol and when it is advised to create your own standard in your application in the <doc:Standard> documentation.

A ``Module`` defines a software subsystem providing distinct and reusable functionality.
Modules can use the constraint mechanism to enforce a set of requirements for the standard used in the Grove-based software where the module is used.
Modules also define dependencies on each other to reuse functionality and can communicate with other modules by offering and collecting information.
You can learn more about modules in the <doc:Module> documentation.

## Topics

### Migrating

- <doc:Migrating-to-Grove>

### Configuration

- <doc:Initial-Setup>
- ``GroveAppDelegate``
- ``Configuration``
- ``SwiftUICore/View/grove(_:)``

### Essential Concepts

- ``Grove/Grove``
- ``Standard``
- ``Module``

### Previews

- ``SwiftUICore/View/previewWith(standard:simulateLifecycle:_:)``
- ``SwiftUICore/View/previewWith(simulateLifecycle:_:)``
- ``Foundation/ProcessInfo/isPreviewSimulator``
- ``LifecycleSimulationOptions``

### Contribute to Grove

- <doc:Contributing-Guide>
- <doc:Grove-Guide>
- <doc:Documentation-Guide>
