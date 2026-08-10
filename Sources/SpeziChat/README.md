<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi Chat



Provides UI components for building chat-based applications.


## Overview

The [SpeziChat](SpeziChat.docc/SpeziChat.md) module provides views that can be used to implement chat-based use cases, such as a message view or a voice input field.

|![Screenshot displaying the regular chat view.](SpeziChat.docc/Resources/ChatView.png#gh-light-mode-only) ![Screenshot displaying the regular chat view.](SpeziChat.docc/Resources/ChatView~dark.png#gh-dark-mode-only)|![Screenshot displaying the text input chat view.](SpeziChat.docc/Resources/ChatView+TextInput.png#gh-light-mode-only) ![Screenshot displaying the text input chat view.](SpeziChat.docc/Resources/ChatView+TextInput~dark.png#gh-dark-mode-only)|![Screenshot displaying the voice input chat view.](SpeziChat.docc/Resources/ChatView+VoiceInput.png#gh-light-mode-only) ![Screenshot displaying the voice input chat view.](SpeziChat.docc/Resources/ChatView+VoiceInput~dark.png#gh-dark-mode-only)
|:--:|:--:|:--:|
|`ChatView`|`ChatView`|`ChatView`|


## Setup


### 1. Add Spezi Chat as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziChat` product.

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
        .product(name: "SpeziChat", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial-Setup.md) to set up the core Spezi infrastructure.

### 2. Configure target properties

As SpeziChat is utilizing the [SpeziSpeech](../SpeziSpeech/README.md) module under the hood for speech interaction capabilities, one needs to ensure that your application has the necessary permissions for microphone access and speech recognition. Follow the steps below to configure the target properties within your Xcode project:

- Open your project settings in Xcode by selecting *PROJECT_NAME > TARGET_NAME > Info* tab.
- You will need to add two entries to the `Custom iOS Target Properties` (so the `Info.plist` file) to provide descriptions for why your app requires these permissions:
   - Add a key named `Privacy - Microphone Usage Description` and provide a string value that describes why your application needs access to the microphone. This description will be displayed to the user when the app first requests microphone access.
   - Add another key named `Privacy - Speech Recognition Usage Description` with a string value that explains why your app requires the speech recognition capability. This will be presented to the user when the app first attempts to perform speech recognition.

These entries are mandatory for apps that utilize microphone and speech recognition features. Failing to provide them will result in your app being unable to access these features.

## Usage

The underlying data model of [SpeziChat](SpeziChat.docc/SpeziChat.md) is a `Chat`. It represents the content of a typical text-based chat between user and system(s). A `Chat` is nothing more than an ordered array of `ChatEntity`s which contain the content of the individual messages.
A `ChatEntity` consists of a `ChatEntity/Role`, a unique identifier, a timestamp as well as an `String`-based content which can contain Markdown-formatted text. In addition, a flag indicates if the `ChatEntity` is complete and no further content will be added.

> [!NOTE]
> The `ChatEntity` is able to store Markdown-based content which in turn is rendered as styled text in the `ChatView`, `MessagesView`, and `MessageView`.

### Chat View

The `ChatView` provides a basic reusable chat view which includes a message input field. The input can be either typed out via the iOS keyboard or provided as voice input and transcribed into written text. It accepts an additional `messagePendingAnimation` parameter to control whether a chat bubble animation is shown for a message that is currently being composed. By default, `messagePendingAnimation` has a value of `nil` and does not show.
In addition, the `ChatView` provides functionality to export the visualized `Chat` as a PDF document, JSON representation, or textual UTF-8 file (see `ChatView/ChatExportFormat`) via a Share Sheet (or Activity View).

```swift
struct ChatTestView: View {
    @State private var chat: Chat = [
        ChatEntity(role: .assistant, content: "Assistant Message!")
    ]


    var body: some View {
        ChatView($chat, exportFormat: .pdf)
            .navigationTitle("SpeziChat")
    }
}
```

> [!NOTE]
> The `ChatView` provides speech-to-text (recognition) as well as text-to-speech (synthesize) accessibility capabilities out-of-the-box via the [`SpeziSpeech`](../SpeziSpeech/README.md) module, facilitating seamless interaction with the content of the `ChatView`.

### Messages View

The `MessagesView` displays a `Chat` containing multiple `ChatEntity`s with different `ChatEntity/Role`s in a typical chat-like fashion.
The `View` automatically scrolls down to the newest message that is added to the passed `Chat` SwiftUI `Binding`.
The `typingIndicator` parameter controls when a typing indicator is shown onscreen for incoming messages to `Chat`.

```swift
struct MessagesViewTestView: View {
    @State private var chat: Chat = [
        ChatEntity(role: .user, content: "User Message!"),
        ChatEntity(role: .assistant, content: "Assistant Message!")
    ]


    var body: some View {
        MessagesView($chat)
    }
}
```

### Message View

The `MessageView` is a reusable SwiftUI `View` to display the contents of a `ChatEntity` within a typical chat message bubble. This bubble is properly aligned according to the associated `ChatEntity/Role`.

```swift
struct MessageViewTestView: View {
    var body: some View {
        VStack {
            MessageView(ChatEntity(role: .user, content: "User Message!"))
            MessageView(ChatEntity(role: .assistant, content: "Assistant Message!"))
            MessageView(ChatEntity(role: .hidden(type: .unknown), content: "System Message (hidden)!"))
        }
            .padding()
    }
}
```

### MessageInput View

The `MessageInputView` is a reusable SwiftUI `View` to handle text-based or speech-based user input. The provided message is attached to the passed `Chat` via a SwiftUI `Binding`.

```swift
struct MessageInputTestView: View {
    @State private var chat: Chat = []
    @State private var disableInput = false


    var body: some View {
        VStack {
            Spacer()
            MessageInputView($chat, messagePlaceholder: "TestMessage")
                .disabled(disableInput)
                /// Get the height of the `MessageInputView` via a SwiftUI `PreferenceKey`
                .onPreferenceChange(MessageInputViewHeightKey.self) { newValue in
                    let messageInputHeight: CGFloat = newValue
                    // ...
                }
        }
    }
}
```

For more information, please refer to the [API documentation](SpeziChat.docc/SpeziChat.md).

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
