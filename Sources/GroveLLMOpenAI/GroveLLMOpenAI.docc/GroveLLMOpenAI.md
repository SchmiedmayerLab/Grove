# ``GroveLLMOpenAI``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Interact with Large Language Models (LLMs) from OpenAI.

## Overview

A module that allows you to interact with GPT-based Large Language Models (LLMs) from OpenAI within your Grove application.
``GroveLLMOpenAI`` provides a pure Swift-based API for interacting with the OpenAI GPT API, building on top of the infrastructure of the [GroveLLM target](../../GroveLLM/GroveLLM.docc/GroveLLM.md).

@Row {
    @Column {
        @Image(source: "LLMOpenAIAPITokenOnboardingStep", alt: "Screenshot displaying the OpenAI API Token Onboarding view from Grove OpenAI") {
            ``LLMOpenAIAPITokenOnboardingStep``
        }
    }
    @Column {
        @Image(source: "LLMOpenAIModelOnboardingStep", alt: "Screenshot displaying the Open AI Model Selection Onboarding Step"){
            ``LLMOpenAIModelOnboardingStep``
        }
    }
    @Column {
        @Image(source: "ChatView", alt: "Screenshot displaying the usage of the LLMOpenAI with the GroveChat Chat View."){
            ``LLMOpenAISession``
        }
    }
}

## Setup

### Add Grove LLM as a Dependency

You need to add the GroveLLM Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) to set up the core Grove infrastructure.

## Grove LLM OpenAI Components

The core components of the ``GroveLLMOpenAI`` target are the ``LLMOpenAISchema``, ``LLMOpenAISession`` as well as ``LLMOpenAIPlatform``. They heavily use the OpenAI API to perform textual inference on the GPT-3.5 or GPT-4 models from OpenAI.

> Important: To utilize an LLM from OpenAI, an OpenAI API Key is required. Ensure that the OpenAI account associated with the key has enough resources to access the specified model as well as enough credits to perform the actual inference.

> Tip: In order to collect the OpenAI API Key or model type from the user, ``GroveLLMOpenAI`` provides the ``LLMOpenAIAPITokenOnboardingStep`` and ``LLMOpenAIModelOnboardingStep`` views which can be used in the onboarding flow of the application.

### LLM OpenAI

``LLMOpenAISchema`` offers a variety of configuration possibilities that are supported by the OpenAI API, such as the model type, the system prompt, the temperature of the model, and many more. These options can be set via the ``LLMOpenAILikeSchema/init(parameters:modelParameters:injectIntoContext:_:)`` initializer and the ``LLMOpenAIParameters`` and ``LLMOpenAIModelParameters``.

- Important: The OpenAI LLM abstractions shouldn't be used on it's own but always used together with the Grove `LLMRunner`.

#### Setup

In order to use OpenAI LLMs, the [GroveLLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md) needs to be initialized in the Grove `Configuration` with the ``LLMOpenAIPlatform``. Only after, the `LLMRunner` can be used to do inference via OpenAI LLMs.
See the [GroveLLM documentation](../../GroveLLM/GroveLLM.docc/GroveLLM.md) for more details.

```swift
import Grove
import GroveLLM
import GroveLLMOpenAI

class LLMOpenAIAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
         Configuration {
             LLMRunner {
                LLMOpenAIPlatform()
            }
        }
    }
}
```

#### Usage

The code example below showcases the interaction with the OpenAI LLMs within the Grove ecosystem through the the [GroveLLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md), which is injected into the SwiftUI `Environment` via the `Configuration` shown above.

The ``LLMOpenAISchema`` defines the type and configurations of the to-be-executed ``LLMOpenAISession``. This transformation is done via the [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md) that uses the ``LLMOpenAIPlatform``. The inference via ``LLMOpenAILikeSession/generate()`` returns an `AsyncThrowingStream` that yields all generated `String` pieces.

The ``LLMOpenAISession`` contains the ``LLMOpenAILikeSession/context`` property which holds the entire history of the model interactions. This includes the system prompt, user input, but also assistant responses.
Ensure the property always contains all necessary information, as the ``LLMOpenAILikeSession/generate()`` function executes the inference based on the ``LLMOpenAILikeSession/context``

```swift
import GroveLLM
import GroveLLMOpenAI
import SwiftUI

struct LLMOpenAIDemoView: View {
    @Environment(LLMRunner.self) var runner
    @State var responseText = ""

    var body: some View {
        Text(responseText)
            .task {
                // Instantiate the `LLMOpenAISchema` to an `LLMOpenAISession` via the `LLMRunner`.
                let llmSession: LLMOpenAISession = runner(
                    with: LLMOpenAISchema(
                        parameters: .init(
                            modelType: .gpt4o,
                            systemPrompt: "You're a helpful assistant that answers questions from users.",
                            overwritingAuthToken: "abc123"
                        )
                    )
                )

                do {
                    for try await token in try await llmSession.generate() {
                        responseText.append(token)
                    }
                } catch {
                    // Handle errors here. E.g., you can use `ViewState` and `viewStateAlert` from GroveViews.
                }
            }
    }
}
```

#### LLM Function Calling

The OpenAI GPT-based LLMs provide function calling capabilities in order to enable a structured, bidirectional, and reliable communication between the OpenAI LLMs and external tools, such as the Grove ecosystem.
``GroveLLMOpenAI`` provides a declarative Domain Specific Language to make LLM function calling as seamless as possible within Grove.
An extensive documentation can be found in <doc:FunctionCalling>.

### Onboarding Flow

The ``LLMOpenAIAPITokenOnboardingStep`` provides a view that can be used for the user to enter an OpenAI API key during onboarding in your Grove application. The example below showcases of how to can add an OpenAI onboarding step within an application created from the Grove Template Application below.

First, create a new view to show the onboarding step:

```swift
import GroveLLMOpenAI
import GroveOnboarding
import SwiftUI

struct OpenAIAPIKey: View {
    @Environment(OnboardingNavigationPath.self) private var onboardingNavigationPath: OnboardingNavigationPath

    var body: some View {
        LLMOpenAIAPITokenOnboardingStep {
            onboardingNavigationPath.nextStep()
        }
    }
}
```

This view can then be added to the `OnboardingFlow` within the Grove Template Application:

```swift
import GroveViews
import SwiftUI

struct OnboardingFlow: View {
    @AppStorage(StorageKeys.onboardingFlowComplete) var completedOnboardingFlow = false

    var body: some View {
        ManagedNavigationStack(didComplete: $completedOnboardingFlow) {
            // ... other steps
            OpenAIAPIKey()
            // ... other steps
        }
    }
}
```

Now the OpenAI API Key entry view will appear within your application's onboarding process. The API Key entered will be persisted across application launches.

## Topics

### LLM OpenAI abstraction

- ``LLMOpenAISchema``
- ``LLMOpenAISession``

### LLM Execution

- ``LLMOpenAIPlatform``
- ``LLMOpenAIPlatformConfiguration``

### Onboarding

- ``LLMOpenAIAPITokenOnboardingStep``
- ``LLMOpenAIModelOnboardingStep``

### LLM Configuration

- ``LLMOpenAIParameters``
- ``LLMOpenAIModelParameters``

### Misc

- ``LLMOpenAIError``
