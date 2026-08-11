# ``SpeziSpeechRecognizer``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Provides speech-to-text capabilities via Apple's `Speech` framework.

## Overview

The Spezi ``SpeechRecognizer`` encapsulates the functionality of Apple's `Speech` framework, more specifically, the `SFSpeechRecognizer`.
It provides methods to start and stop voice recognition and publishes the state of recognition and its availability.

## Setup

### 1. Add Spezi Speech as a Dependency

You need to add the SpeziSpeech Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Spezi, follow the [Spezi setup article](../../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

### 2. Configure the `SpeechRecognizer` in the Spezi `Configuration`

The module needs to be registered in a Spezi-based application using the [`configuration`](../../Spezi/Spezi.docc/Spezi.md)
in a [`SpeziAppDelegate`](../../Spezi/Spezi.docc/Spezi.md):
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            SpeechRecognizer()
            // ...
        }
    }
}
```
> Tip: You can learn more about a [`Module` in the Spezi documentation](../../Spezi/Spezi.docc/Module/Module.md).

### 3. Configure target properties

To ensure that your application has the necessary permissions for microphone access and speech recognition, follow the steps below to configure the target properties within your Xcode project:

- Open your project settings in Xcode by selecting *PROJECT_NAME > TARGET_NAME > Info* tab.
- You will need to add two entries to the `Custom iOS Target Properties` (so the `Info.plist` file) to provide descriptions for why your app requires these permissions:
   - Add a key named `Privacy - Microphone Usage Description` and provide a string value that describes why your application needs access to the microphone. This description will be displayed to the user when the app first requests microphone access.
   - Add another key named `Privacy - Speech Recognition Usage Description` with a string value that explains why your app requires the speech recognition capability. This will be presented to the user when the app first attempts to perform speech recognition.

These entries are mandatory for apps that utilize microphone and speech recognition features. Failing to provide them will result in your app being unable to access these features.

## Example

The code example demonstrates the usage of the Spezi ``SpeechRecognizer`` within a minimal SwiftUI application.

```swift
struct SpeechTestView: View {
   // Get the `SpeechRecognizer` from the SwiftUI `Environment`.
   @Environment(SpeechRecognizer.self) private var speechRecognizer
   // The transcribed message from the user's voice input.
   @State private var message = ""


   var body: some View {
        VStack {
             // Button used to start and stop recording by triggering the `microphoneButtonPressed()` function.
             Button("Record") {
                 microphoneButtonPressed()
             }
                 .padding(.bottom)

             Text(message)
         }
   }


   private func microphoneButtonPressed() {
      if speechRecognizer.isRecording {
         // If speech is currently recognized, stop the transcribing.
         speechRecognizer.stop()
      } else {
         // If the recognizer is idle, start a new recording.
         Task {
            do {
               // The `speechRecognizer.start()` function returns an `AsyncThrowingStream` that yields the transcribed text.
               for try await result in speechRecognizer.start() {
                  // Access the string-based result of the transcribed result.
                  message = result.bestTranscription.formattedString
               }
            }
         }
      }
   }
}
```

## Topics

- ``SpeechRecognizer``
