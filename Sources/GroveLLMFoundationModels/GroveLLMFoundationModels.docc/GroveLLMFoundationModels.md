# ``GroveLLMFoundationModels``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Run Apple's own language models through the Grove LLM abstractions.

## Overview

``GroveLLMFoundationModels`` puts Apple's `FoundationModels` behind the same `LLMPlatform`, `LLMSchema`, and
`LLMSession` protocols the remote providers use, so a view built against `GroveLLMOpenAI` runs unchanged against a
model that never leaves the device.

Two models are available, both without an account, an API key, or any configuration:

- ``LLMFoundationModelsModelType/onDevice`` — the model that ships with the operating system.
- ``LLMFoundationModelsModelType/privateCloudCompute`` — Apple's larger server model, run in Private Cloud Compute.

Neither is guaranteed to be there. The on-device model needs an eligible device with Apple Intelligence turned on, and
Private Cloud Compute needs an eligible device and a reachable system service, so ask
``LLMFoundationModelsPlatform/availability(of:)`` before offering one.

> Important: `FoundationModels` gained the `LanguageModel` protocol in iOS 27, which is what lets one session type
serve both the on-device and the Private Cloud Compute model. Everything in this target is therefore available from
iOS 27, macOS 27, and visionOS 27.

### Setup

Add ``LLMFoundationModelsPlatform`` to the `LLMRunner` in the Grove `Configuration`:

```swift
import Grove
import GroveLLM
import GroveLLMFoundationModels

class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            LLMRunner {
                LLMFoundationModelsPlatform()
            }
        }
    }
}
```

### Usage

```swift
struct LLMFoundationModelsChatView: View {
    @Environment(LLMRunner.self) var runner
    @State var model: LLMFoundationModelsSession?

    var body: some View {
        LLMChatViewSchema(
            with: LLMFoundationModelsSchema(
                modelType: .onDevice,
                systemPrompt: "You're a helpful assistant that answers questions from users."
            )
        )
    }
}
```

### Checking Availability

```swift
struct ModelPicker: View {
    @Environment(LLMFoundationModelsPlatform.self) var platform
    @State private var modelType: LLMFoundationModelsModelType = .onDevice

    var body: some View {
        Picker("Model", selection: $modelType) {
            ForEach(LLMFoundationModelsModelType.allCases, id: \.self) { modelType in
                Text(String(describing: modelType))
                    .tag(modelType)
            }
        }
        .onChange(of: modelType) { _, newValue in
            if case .unavailable(let reason) = platform.availability(of: newValue) {
                // Tell the user why, e.g. that Apple Intelligence has to be turned on.
            }
        }
    }
}
```

### Images

The models that report the `vision` capability take images alongside the text of a message, and `GroveLLM` passes on
whatever an `LLMContextEntity` carries. A model without the capability rejects attachments outright, so for those the
images are dropped and the text is sent on its own rather than failing the turn.

### What This Target Doesn't Cover Yet

- **Function calling.** `FoundationModels` tools are built around `@Generable` argument types, while `LLMTool`
  describes its parameters with a runtime JSON schema. Bridging the two needs a dynamic `GenerationSchema`, which is
  not in place yet — an ``LLMFoundationModelsSession`` is not a `ToolCallLLMSession`.
- **Structured output.** `FoundationModels`' guided generation has no counterpart in the `LLMSession` protocol, which
  streams `String`s.
- **Reasoning summaries.** Private Cloud Compute reasons, but the summaries are not yet surfaced as
  `assistantThinking` entities the way `GroveLLMOpenAI` surfaces OpenAI's.

## Topics

### Configuration

- ``LLMFoundationModelsPlatform``
- ``LLMFoundationModelsPlatformConfiguration``
- ``LLMFoundationModelsSchema``
- ``LLMFoundationModelsModelType``

### Execution

- ``LLMFoundationModelsSession``

### Availability and Errors

- ``LLMFoundationModelsAvailability``
- ``LLMFoundationModelsError``
