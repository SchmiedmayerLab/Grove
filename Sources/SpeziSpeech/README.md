<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziSpeech


Recognize and synthesize natural language speech.


## Overview

The Spezi Speech component provides an easy and convenient way to recognize (speech-to-text) and synthesize (text-to-speech) natural language content, facilitating seamless interaction with an application. It builds on top of Apple's [Speech](https://developer.apple.com/documentation/speech/) and [AVFoundation](https://developer.apple.com/documentation/avfoundation/) frameworks.


## Setup


### 1. Add Spezi Speech as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziSpeechRecognizer` and `SpeziSpeechSynthesizer` products.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SpeziSpeechRecognizer", package: "Spezi"),
        .product(name: "SpeziSpeechSynthesizer", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

### 2. Configure the `SpeechRecognizer` and the `SpeechSynthesizer` in the Spezi `Configuration`

The `SpeechRecognizer` and `SpeechSynthesizer` modules need to be registered in a Spezi-based application using the `configuration`
in a `SpeziAppDelegate`:
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            SpeechRecognizer()
            SpeechSynthesizer()
            // ...
        }
    }
}
```

> [!NOTE]
> You can learn more about a [`Module`](../Spezi/Spezi.docc/Module/Module.md) in the Spezi documentation.

### 3. Configure target properties

To ensure that your application has the necessary permissions for microphone access and speech recognition, follow the steps below to configure the target properties within your Xcode project:

- Open your project settings in Xcode by selecting *PROJECT_NAME > TARGET_NAME > Info* tab.
- You will need to add two entries to the `Custom iOS Target Properties` (so the `Info.plist` file) to provide descriptions for why your app requires these permissions:
   - Add a key named `Privacy - Microphone Usage Description` and provide a string value that describes why your application needs access to the microphone. This description will be displayed to the user when the app first requests microphone access.
   - Add another key named `Privacy - Speech Recognition Usage Description` with a string value that explains why your app requires the speech recognition capability. This will be presented to the user when the app first attempts to perform speech recognition.

These entries are mandatory for apps that utilize microphone and speech recognition features. Failing to provide them will result in your app being unable to access these features.

## Example

`SpeechTestView` provides a demonstration of the capabilities of Spezi Speech.
It showcases the interaction with the `SpeechRecognizer` to provide speech-to-text capabilities and the `SpeechSynthesizer` to generate speech from text.


```swift
struct SpeechTestView: View {
   // Get the `SpeechRecognizer` and `SpeechSynthesizer` from the SwiftUI `Environment`.
   @Environment(SpeechRecognizer.self) private var speechRecognizer
   @Environment(SpeechSynthesizer.self) private var speechSynthesizer
   // The transcribed message from the user's voice input.
   @State private var message = ""


   var body: some View {
      VStack {
         // Button used to start and stop recording by triggering the `microphoneButtonPressed()` function.
         Button("Record") {
             microphoneButtonPressed()
         }
             .padding(.bottom)

         // Button used to start and stop playback of the transcribed message by triggering the `playbackButtonPressed()` function.
         Button("Playback") {
             playbackButtonPressed()
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

For more information, please refer to the [SpeziSpeechRecognizer](../SpeziSpeechRecognizer/SpeziSpeechRecognizer.docc/SpeziSpeechRecognizer.md) and [SpeziSpeechSynthesizer](../SpeziSpeechSynthesizer/SpeziSpeechSynthesizer.docc/SpeziSpeechSynthesizer.md) documentation.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
