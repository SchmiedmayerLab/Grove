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
        @Image(source: "Onboarding", alt: "Screenshot displaying an onboarding page with a title, information areas and floating action buttons.") {
            [Grove Onboarding](../../GroveOnboarding/GroveOnboarding.docc/GroveOnboarding.md): welcome, information and permission pages that read like the system's own.
        }
    }
    @Column {
        @Image(source: "AccountSetup", alt: "Screenshot displaying the account setup view with email and password prompt and Sign In with Apple button using the Grove Account module.") {
            [Grove Account](../../GroveAccount/GroveAccount.docc/GroveAccount.md): sign-up, sign-in and account details, backed by Firebase or a service of your own.
        }
    }
    @Column {
        @Image(source: "Consent", alt: "Screenshot displaying a signed consent document.") {
            [Grove Consent](../../GroveConsent/GroveConsent.docc/GroveConsent.md): Markdown consent documents with toggles, choices and a signature, exported as PDF.
        }
    }
    @Column {
        @Image(source: "Schedule", alt: "Screenshot displaying the tasks scheduled for a day.") {
            [Grove Scheduler](../../GroveScheduler/GroveScheduler.docc/GroveScheduler.md): tasks on a schedule, listed for the day and completed in place.
        }
    }
}
@Row {
    @Column {
        @Image(source: "PairedDevices", alt: "Screenshot displaying Grove Devices and Bluetooth pairing user interface.") {
            [Grove Bluetooth](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) and [Grove Devices](../../GroveDevices/GroveDevices.docc/GroveDevices.md): pairing and reading Bluetooth health devices.
        }
    }
    @Column {
        @Image(source: "Questionnaire", alt: "Screenshot displaying a questionnaire page with a choice, a multiple choice, a slider and a time question on cards.") {
            [Grove Questionnaire](../../GroveQuestionnaire/GroveQuestionnaire.docc/GroveQuestionnaire.md): questionnaires declared in Swift or imported from FHIR, with branching, scoring and validation.
        }
    }
    @Column {
        @Image(source: "Chat", alt: "Screenshot displaying a conversation with an attached photo and a generated picture.") {
            [Grove Chat](../../GroveChat/GroveChat.docc/GroveChat.md): conversations with pictures, citations and follow-ups, streamed as the model answers.
        }
    }
    @Column {
        @Image(source: "ToolCall", alt: "Screenshot displaying a conversation in which the assistant calls a function to read health samples before answering.") {
            [Grove LLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md): one chat over OpenAI, Anthropic, Gemini, Apple's Foundation Models or a model running on the device, with function calling into your app.
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
