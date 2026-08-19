# ``GroveChat``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Provides UI components for building chat-based applications.

## Overview

The ``GroveChat`` module provides views that can be used to implement chat-based use cases, such as a message view or a voice input field.

@Row {
    @Column {
        @Image(source: "ChatView.png", alt: "Screenshot displaying the regular chat view.") {
            A ``ChatView`` allows you to display a messages in a typical chat-like manner.
        }
    }
    @Column {
        @Image(source: "ChatView+TextInput.png", alt: "Screenshot displaying the text input chat view.") {
            A ``ChatView`` enables the input of new messages via text.
        }
    }
    @Column {
        @Image(source: "ChatView+VoiceInput.png", alt: "Screenshot displaying the voice input chat view.") {
            A ``ChatView`` allows users to use their voice for input (speech-to-text).
        }
    }
}

## Setup

### 1. Add Grove Chat as a Dependency

You need to add the Grove Chat Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) to setup the core Grove infrastructure.

### 2. Configure target properties

As ``GroveChat`` is utilizing the [GroveSpeech](../../GroveSpeech/GroveSpeech.docc/GroveSpeech.md) module under the hood for speech interaction capabilities, one needs to ensure that your application has the necessary permissions for microphone access and speech recognition. Follow the steps below to configure the target properties within your Xcode project:

- Open your project settings in Xcode by selecting *PROJECT_NAME > TARGET_NAME > Info* tab.
- You will need to add two entries to the `Custom iOS Target Properties` (so the `Info.plist` file) to provide descriptions for why your app requires these permissions:
   - Add a key named `Privacy - Microphone Usage Description` and provide a string value that describes why your application needs access to the microphone. This description will be displayed to the user when the app first requests microphone access.
   - Add another key named `Privacy - Speech Recognition Usage Description` with a string value that explains why your app requires the speech recognition capability. This will be presented to the user when the app first attempts to perform speech recognition.

These entries are mandatory for apps that utilize microphone and speech recognition features. Failing to provide them will result in your app being unable to access these features.

## Usage

The underlying data model of ``GroveChat`` is a ``Chat``. It represents the content of a typical text-based chat between user and system(s). A ``Chat`` is nothing more than an ordered array of ``ChatEntity``s which contain the content of the individual messages.
A ``ChatEntity`` consists of a ``ChatEntity/Role-swift.enum``, a timestamp, and its ``ChatEntity/Content-swift.struct`` — Markdown-formatted text, images, or both. In addition, a flag indicates if the `ChatEntity` is complete and no further content will be added.

> Tip: The ``ChatEntity`` is able to store Markdown-based content which in turn is rendered as styled text in the ``ChatView`` and ``MessagesView``.

### Chat View

The ``ChatView`` provides a basic reusable chat view which includes a message input field. The input can be either typed out via the iOS keyboard or provided as voice input and transcribed into written text. It accepts an additional `messagePendingAnimation` parameter to control whether a chat bubble animation is shown for a message that is currently being composed. By default, `messagePendingAnimation` has a value of `nil` and does not show.
In addition, the ``ChatView`` provides functionality to export the visualized ``Chat`` as a PDF document, JSON representation, or textual UTF-8 file (see ``ChatView/ChatExportFormat``) via a Share Sheet (or Activity View).

```swift
struct ChatTestView: View {
    @State private var chat: Chat = [
        ChatEntity(role: .assistant(.response), text: "Assistant Message!")
    ]


    var body: some View {
        ChatView($chat, exportFormat: .pdf)
            .navigationTitle("GroveChat")
    }
}
```

- Tip: The ``ChatView`` provides speech-to-text (recognition) as well as text-to-speech (synthesize) accessibility capabilities out-of-the-box via the [`GroveSpeech`](../../GroveSpeech/GroveSpeech.docc/GroveSpeech.md) module, facilitating seamless interaction with the content of the ``ChatView``.

### Messages View

The ``MessagesView`` displays a ``Chat`` containing multiple ``ChatEntity``s with different ``ChatEntity/Role``s in a typical chat-like fashion.
The `View` automatically scrolls down to the newest message that is added to the passed ``Chat`` SwiftUI `Binding`.
The `typingIndicator` parameter controls when a typing indicator is shown onscreen for incoming messages to `Chat`.

```swift
struct MessagesViewTestView: View {
    @State private var chat: Chat = [
        ChatEntity(role: .user, text: "User Message!"),
        ChatEntity(role: .assistant(.response), text: "Assistant Message!")
    ]


    var body: some View {
        MessagesView($chat)
    }
}
```

### Message Content

A message is an ordered list of ``ChatEntity/Content-swift.struct/Part``s — text, images and files, in the order
they are shown — which is how both the OpenAI API and Apple's `FoundationModels` model a message. The common cases
stay one-liners: ``ChatEntity/Content-swift.struct/text(_:)`` builds text content and
``ChatEntity/Content-swift.struct/text`` reads it back.

Images may either be in-memory ``PlatformImage``s — for example ones the user attached from their photo library —
or remote `URL`s that are loaded lazily. Files are copies the app owns, so they outlive the picker that produced
them.

```swift
struct AttachmentTestView: View {
    @State private var chat: Chat = [
        ChatEntity(role: .user, content: .images([.image(screenshot)], text: "What is this?")),
        ChatEntity(role: .assistant(.response), text: "That's a chest X-ray.")
    ]


    var body: some View {
        ChatView($chat)
    }
}
```

On iOS and visionOS 26+, the composer lets the user attach images itself, so no extra wiring is needed to accept
them. Use ``SwiftUICore/View/chatAttachments(_:)`` to choose what may be attached, or to take the attach button away:

```swift
ChatView($chat)
    .chatAttachments([])    // a chat that only takes text
```

Tapping any image in the conversation — attached or generated — opens it full screen, pages through the rest of
the message's images, and offers the one on screen to the share sheet. A file opens in Quick Look, so every format
the system can preview works without the chat knowing about any of them.

### Showing Where an Answer Came From

A model that searches the web or reads a document reports what it drew on, and those sources arrive as
``ChatEntity/Citation``s on the message. The chat shows them as one quiet line under the answer rather than as
links through the text; tapping it lists them, and a web source opens in a Safari view without leaving the
conversation.

```swift
ChatEntity(
    role: .assistant(.response),
    content: .text("The gateway runs LiteLLM."),
    citations: [.init(title: "AI API Gateway", source: .web(url))]
)
```

### Thinking and Tool Calls

Reasoning models expose their progress via ``ChatEntity/Role-swift.enum/assistant(_:)`` entities carrying
``ChatEntity/Role-swift.enum/AssistantMessageKind-swift.enum/thinking(startDate:endDate:)``, which render as a live
timer while the model works and as a "Thought for …" disclosure once it finishes. Tool calls and their responses use
``ChatEntity/Role-swift.enum/AssistantMessageKind-swift.enum/toolCall`` and
``ChatEntity/Role-swift.enum/AssistantMessageKind-swift.enum/toolResponse``.

Use ``MessagesView/MessagesVisibility`` to choose which of these the user sees:

```swift
MessagesView($chat, messagesVisibility: .init(hiddenMessages: .all, toolCalls: .visible))
```

### Reporting What the Assistant Is Doing

A ``ChatView`` shows a conversation; it does not run one. Tell it what is happening and it adapts: while an answer
is in flight the composer will not send a second message, and the send button becomes a stop button when there is
something to stop.

```swift
struct ConversationView: View {
    @State private var chat = Chat()
    @State private var lastError: (any Error)?

    var body: some View {
        ChatView($chat)
            .chatEmptyState("Ask About Your Medication", description: "Answers come from your care team's guidance.")
            .chatGenerating(session.state == .generating) {
                session.cancel()
            }
            .chatError(lastError) {
                lastError = nil
                respond()
            }
    }
}
```

A failure reported this way appears inline, where the answer would have been, rather than as an alert that takes
the conversation away — with a retry next to it.

## Topics

### Display messages

- ``ChatView``
- ``MessagesView``

### Message models

- ``Chat``
- ``ChatEntity``
- ``ChatEntity/Role-swift.enum``
- ``ChatEntity/Content-swift.struct``
- ``ChatEntity/Content-swift.struct/Part``
- ``ChatEntity/Content-swift.struct/File``
- ``ChatEntity/Citation``
- ``ChatEntity/HiddenMessageType``
- ``PlatformImage``

### Reporting state

- ``SwiftUICore/View/chatGenerating(_:onCancel:)``
- ``SwiftUICore/View/chatError(_:retry:)``
- ``SwiftUICore/View/chatEmptyState(_:description:systemImage:)``
- ``SwiftUICore/View/chatEmptyState(_:)``

### Composing messages

- ``ChatAttachmentKinds``
- ``ChatAttachmentStore``
- ``ChatAttachmentStorage``
- ``FileSystemChatAttachmentStorage``
- ``SwiftUICore/View/chatAttachments(_:)``
- ``SwiftUICore/View/speechToText(_:)``

### Choosing what is shown

- ``MessagesView/MessagesVisibility``
- ``ChatMessageActions``
- ``ChatMessageActionsPresentation``
- ``SwiftUICore/View/chatMessageActions(_:presentation:)``

### Styling

- ``SwiftUICore/View/chatViewInsets(_:)``
- ``SwiftUICore/View/chatAccentColor(_:)``
