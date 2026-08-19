# ``GroveLLMOpenAIRealtime``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Interact with OpenAI's Realtime API for bidirectional audio and voice conversations.

## Overview

A module that allows you to interact with OpenAI's Realtime API for real-time, bidirectional audio conversations with GPT-based Large Language Models (LLMs) within your Grove application.
``GroveLLMOpenAIRealtime`` provides a pure Swift-based API for interacting with the OpenAI Realtime API, enabling natural voice conversations with automatic speech recognition, voice activity detection, and real-time audio streaming. It builds on top of the infrastructure of the [GroveLLM target](../../GroveLLM/GroveLLM.docc/GroveLLM.md).

## Setup

### Add Grove LLM as a Dependency

You need to add the GroveLLM Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) to set up the core Grove infrastructure.

## Grove LLM OpenAI Realtime Components

The core components of the ``GroveLLMOpenAIRealtime`` target are the ``LLMOpenAIRealtimeSchema``, ``LLMOpenAIRealtimeSession`` as well as ``LLMOpenAIRealtimePlatform``. They use the OpenAI Realtime API to enable bidirectional voice conversations with GPT Realtime and similar models.

> Important: To utilize the OpenAI Realtime API, an OpenAI API Key is required. Ensure that the OpenAI account associated with the key has access to the Realtime API models and enough credits to perform the inference.

> Tip: To collect the OpenAI API Key from the user, ``GroveLLMOpenAIRealtime`` leverages the `LLMOpenAIAPITokenOnboardingStep` view from `GroveLLMOpenAI` which can be used in the onboarding flow of the application.

### LLM OpenAI Realtime

``LLMOpenAIRealtimeSchema`` offers a variety of configuration possibilities supported by the OpenAI Realtime API, such as the model type, system prompt, voice selection, turn detection settings, and transcription options. These options can be set via the ``LLMOpenAIRealtimeSchema/init(parameters:injectIntoContext:_:)`` initializer and the ``LLMOpenAIRealtimeParameters`` type.

- Important: The OpenAI Realtime LLM abstractions shouldn't be used on their own but always used together with the Grove `LLMRunner`.

#### Setup

In order to use OpenAI Realtime LLMs, the [GroveLLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md) needs to be initialized in the Grove `Configuration` with the ``LLMOpenAIRealtimePlatform``. Only after, the `LLMRunner` can be used to perform real-time voice interactions via OpenAI Realtime LLMs.
See the [GroveLLM documentation](../../GroveLLM/GroveLLM.docc/GroveLLM.md) for more details.

```swift
import Grove
import GroveLLM
import GroveLLMOpenAI
import GroveLLMOpenAIRealtime

class LLMOpenAIRealtimeAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
         Configuration {
             LLMRunner {
                LLMOpenAIRealtimePlatform()
            }
        }
    }
}
```

#### Usage

The code example below showcases the interaction with OpenAI Realtime LLMs within the Grove ecosystem through the [GroveLLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md), which is injected into the SwiftUI `Environment` via the `Configuration` shown above.

The ``LLMOpenAIRealtimeSchema`` defines the type and configurations of the to-be-executed ``LLMOpenAIRealtimeSession``. This transformation is done via the [`LLMRunner`](../../GroveLLM/GroveLLM.docc/GroveLLM.md) that uses the ``LLMOpenAIRealtimePlatform``. The inference via ``LLMOpenAIRealtimeSession/generate()`` returns an `AsyncThrowingStream` that yields all generated text transcript pieces.

```swift
import GroveLLM
import GroveLLMOpenAIRealtime
import SwiftUI

struct LLMOpenAIRealtimeDemoView: View {
    @Environment(LLMRunner.self) var runner
    @State var responseText = ""

    var body: some View {
        Text(responseText)
            .task {
                // Instantiate the `LLMOpenAIRealtimeSchema` to an `LLMOpenAIRealtimeSession` via the `LLMRunner`.
                let llmSession: LLMOpenAIRealtimeSession = runner(
                    with: LLMOpenAIRealtimeSchema(
                        parameters: .init(
                            modelType: .gpt4oRealtime,
                            systemPrompt: "You're a helpful assistant that answers questions from users.",
                            turnDetectionSettings: .semantic(),
                            transcriptionSettings: .init(model: .gpt4oTranscribe)
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

#### Context Management

The ``LLMOpenAIRealtimeSession`` maintains conversation history through its ``LLMOpenAIRealtimeSession/context`` property, but the way this context is populated differs based on your usage pattern.

**Text-Based Inference**: When using ``LLMOpenAIRealtimeSession/generate()`` for text-based interactions, you must manually append user input to the context using `context.append(userMessage:)` before calling `generate()`. The `generate()` function will then use this last appended message to trigger the model's response. The generated text output is both returned as an `AsyncThrowingStream<String, Error>` and automatically added to the context.

**Audio-Based Inference**: When using audio input with transcription enabled (via ``LLMRealtimeTranscriptionSettings``), the ``LLMOpenAIRealtimeSession`` automatically manages the context for you. As the user speaks and the model responds, transcripts of both the user's speech and the assistant's responses are automatically appended to the ``LLMOpenAIRealtimeSession/context``. You don't need to manually populate the context in this mode, it serves as a read-only conversation history that updates in real-time.

**Displaying the Conversation**: The ``LLMOpenAIRealtimeSession/context`` is fully compatible with existing Grove views such as `LLMChatView` from GroveChat. You can directly bind the context to these views to display the conversation history, whether you're using text-based or audio-based interactions. The context provides a complete transcript of the entire conversation, including both user messages and assistant responses.


#### Audio Streaming

One of the key features of ``GroveLLMOpenAIRealtime`` is bidirectional audio streaming. You can send user audio to the API and receive assistant audio responses in real-time.

**Sending User Audio**

User audio can be streamed to the Realtime API using the ``LLMOpenAIRealtimeSession/appendUserAudio(_:)`` method. Audio must be provided as 16-bit PCM mono audio at 24 kHz sample rate.

```swift
// Assuming you have audio data from a microphone
while let audioChunk = audioRecorder.readPCM16Data() {
    try await llmSession.appendUserAudio(audioChunk)
}
```

**Receiving Assistant Audio**

The assistant's voice response can be streamed back as 16-bit PCM audio at 24 kHz using the ``LLMOpenAIRealtimeSession/listen()`` method:

```swift
for try await pcm16Audio in try await llmSession.listen() {
    // Play the audio chunk through your audio player
    audioPlayer.play(pcm16Audio)
}
```

> Important: Audio data must be in 16-bit PCM (little-endian), mono, 24 kHz format. No resampling or format conversion is performed by ``GroveLLMOpenAIRealtime``.

#### Turn Detection

The Realtime API supports automatic turn detection using Voice Activity Detection (VAD). This allows the model to automatically detect when the user has finished speaking and begin responding.

``GroveLLMOpenAIRealtime`` provides two types of turn detection via ``LLMRealtimeTurnDetectionSettings``:

**Server VAD**

Basic voice activity detection that chunks audio based on detected periods of silence:

```swift
let parameters = LLMOpenAIRealtimeParameters(
    modelType: .gpt4oRealtime,
    turnDetectionSettings: .server(
        .init(
            threshold: 0.5,                         // Activation threshold (0.0-1.0)
            prefixPadding: .milliseconds(300),      // Audio before speech
            silenceDuration: .milliseconds(500),    // Silence to detect end
            createResponse: true,                   // Auto-generate response
            interruptResponse: true                 // Allow interruptions
        )
    )
)
```

**Semantic VAD**

Advanced turn detection that uses a semantic model to determine when the user has finished speaking:

```swift
let parameters = LLMOpenAIRealtimeParameters(
    modelType: .gpt4oRealtime,
    turnDetectionSettings: .semantic(
        .init(
            eagerness: .medium,     // How eager to interrupt: .low, .medium, .high, .auto
            createResponse: true,   // Auto-generate response
            interruptResponse: true // Allow interruptions
        )
    )
)
```

**Manual Turn Detection**

If turn detection is disabled (set to `nil`), you can manually signal the end of the user's turn using ``LLMOpenAIRealtimeSession/endUserTurn()``:

```swift
// Send audio chunks
try await llmSession.appendUserAudio(audioData)

// Manually commit and trigger response
try await llmSession.endUserTurn()
```

#### Transcription

The Realtime API can automatically transcribe user audio input into text. Configure transcription using ``LLMRealtimeTranscriptionSettings``:

```swift
let parameters = LLMOpenAIRealtimeParameters(
    modelType: .gpt4oRealtime,
    transcriptionSettings: .init(
        model: .gpt4oTranscribe,                // or .gpt4oMiniTranscribe, .whisper1
        language: .init(identifier: "en"),      // Optional: specify language
        prompt: "Expect medical terminology"    // Optional: guide transcription
    )
)
```

When transcription is enabled, the transcripts are automatically appended to the ``LLMOpenAIRealtimeSession/context``.

#### Voice Selection

You can select from multiple OpenAI voices for the assistant's audio output:

```swift
let parameters = LLMOpenAIRealtimeParameters(
    modelType: .gpt4oRealtime,
    voice: .alloy  // Options: .alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse
)
```

Each voice has distinct characteristics:
- `alloy`: Neutral and balanced
- `ash`: Clear and precise
- `ballad`: Melodic and smooth
- `coral`: Warm and friendly
- `echo`: Resonant and deep
- `sage`: Calm and thoughtful
- `shimmer`: Bright and energetic
- `verse`: Versatile and expressive

#### LLM Function Calling

Like the standard OpenAI API, the Realtime API supports function calling to enable structured communication between the LLM and external tools. ``GroveLLMOpenAIRealtime`` provides the same declarative Domain Specific Language for function calling as `GroveLLMOpenAI`.

For extensive documentation on function calling, refer to the [GroveLLMOpenAI Function Calling documentation](../../GroveLLMOpenAI/GroveLLMOpenAI.docc/ToolCalling.md).

### Session Management

The ``LLMOpenAIRealtimeSession`` maintains a WebSocket connection to the OpenAI Realtime API. You can cancel the session at any time using ``LLMOpenAIRealtimeSession/cancel()``:

```swift
llmSession.cancel()  // Closes the connection and ends all streams
```

The session will automatically clean up when deallocated.

## Topics

### LLM OpenAI Realtime abstraction

- ``LLMOpenAIRealtimeSchema``
- ``LLMOpenAIRealtimeSession``

### LLM Execution

- ``LLMOpenAIRealtimePlatform``

### LLM Configuration

- ``LLMOpenAIRealtimeParameters``
- ``LLMRealtimeTurnDetectionSettings``
- ``LLMRealtimeTranscriptionSettings``
