# ``SpeziSpeechSynthesizer``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Provides text-to-speech capabilities via Apple's `AVFoundation` framework.

## Overview

The Spezi ``SpeechSynthesizer`` encapsulates the functionality of Apple's `AVFoundation` framework, more specifically, the `AVSpeechSynthesizer`.
It provides methods to start and stop voice synthesizing and publishes the state of the process.

## Setup

### 1. Add Spezi Speech as a Dependency

You need to add the SpeziSpeech Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Spezi, follow the [Spezi setup article](../../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

### 2. Configure the `SpeechSynthesizer` in the Spezi `Configuration`

The module needs to be registered in a Spezi-based application using the [`configuration`](../../Spezi/Spezi.docc/Spezi.md)
in a [`SpeziAppDelegate`](../../Spezi/Spezi.docc/Spezi.md):
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            SpeechSynthesizer()
            // ...
        }
    }
}
```
> Tip: You can learn more about a [`Module` in the Spezi documentation](../../Spezi/Spezi.docc/Module/Module.md).

## Example

The code example demonstrates the usage of the Spezi ``SpeechSynthesizer`` within a minimal SwiftUI application.

```swift
struct SpeechTestView: View {
   // Get the `SpeechSynthesizer` from the SwiftUI `Environment`.
   @Environment(SpeechSynthesizer.self) private var speechSynthesizer
   // A textual message that will be synthesized to natural language speech.
   private let message = "Hello, this is the SpeziSpeech framework!"


   var body: some View {
        // Button used to start and stop playback of the transcribed message by triggering the `playbackButtonPressed()` function.
        Button("Playback") {
            playbackButtonPressed()
        }
   }


   private func playbackButtonPressed() {
      if speechSynthesizer.isSpeaking {
         // If speech is currently synthezized, pause the playback.
         speechSynthesizer.pause()
      } else {
         // If synthesizer is idle, start with the text-to-speech functionality.
         speechSynthesizer.speak(message)
      }
   }
}
```

SpeziSpeech also supports selecting voices, including [personal voices](https://support.apple.com/en-us/104993).

The following example shows how a user can be given a choice of voices in their current locale and the selected voice can be used to synthesize speech.

```swift
struct SpeechVoiceSelectionExample: View {
   @Environment(SpeechSynthesizer.self) private var speechSynthesizer
   @State private var selectedVoiceIndex = 0
   @State private var message = ""


   var body: some View {
      VStack {
         TextField("Enter text to be spoken", text: $message)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
          Picker("Voice", selection: $selectedVoiceIndex) {
              ForEach(speechSynthesizer.voices.indices, id: \.self) { index in
                  Text(speechSynthesizer.voices[index].name)
                      .tag(index)
              }
          }
              .pickerStyle(.inline)
              .accessibilityIdentifier("voicePicker")
              .padding()
         Button("Speak") {
            speechSynthesizer.speak(
                message,
                voice: speechSynthesizer.voices[selectedVoiceIndex]
            )
         }
      }
         .padding()
   }
}
```

Personal voices are supported on iOS 17 and above. Users must first [create a personal voice](https://support.apple.com/en-us/104993). Using personal voices also requires obtaining authorization from the user. To request access to any available personal voices, you can use the `getPersonalVoices()` method of the `SpeechSynthesizer`. Personal voices will then become available alongside system voices.


## Topics

- ``SpeechSynthesizer``
