# ``GroveChat``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Provides UI components for building chat-based applications.

## Overview

The ``GroveChat`` module provides the views of a conversation: the messages, the composer they are written in, and everything a message can carry.

@Row {
    @Column {
        @Image(source: "Conversation", alt: "Screenshot displaying a conversation with a photo the user attached and a picture the assistant generated.") {
            A ``ChatView`` lays the conversation out the way a messaging app does: Markdown, attached photos and files, and pictures the assistant draws, which grow out of a placeholder as they arrive.
        }
    }
    @Column {
        @Image(source: "FollowUp", alt: "Screenshot displaying a passage of an answer quoted above the composer, ready for a follow-up question.") {
            Selecting a passage of an answer offers to follow up on it; the quote sits above the composer and goes out with the next message.
        }
    }
    @Column {
        @Image(source: "ImageViewer", alt: "Screenshot displaying a generated picture full screen with a share button.") {
            Any picture opens full screen, zooms, pages through the message's other pictures and shares as an image.
        }
    }
    @Column {
        @Image(source: "Composer", alt: "Screenshot displaying the chat view with the keyboard up and a message being typed.") {
            Messages are typed into the composer, dictated through the microphone next to it, or sent with photos and files attached.
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

### Pictures the Assistant Draws

A generated picture arrives in two steps. While the model is still drawing, the message carries
``ChatEntity/Content-swift.struct/Image/generating``, which the conversation shows as a card of moving dots; when the
picture is there, the card grows to its size and dissolves into it. Sessions from the
[GroveLLM](../../GroveLLM/GroveLLM.docc/GroveLLM.md) module manage this for you; a chat that produces its own
messages appends the placeholder first and replaces it, under the same identifier, once the picture exists.

### Following Up on a Passage

Selecting text in an answer offers a follow-up on it. The passage is quoted above the composer and sent along with
the next message, so a question can point at exactly the sentence it is about. The option is part of the message
actions, which ``SwiftUICore/View/chatMessageActions(_:presentation:)`` chooses from; `.followUp` turns it off, or on by itself.

### Showing Where an Answer Came From

A model that searches the web or reads a document reports what it drew on, and those sources arrive as
``ChatEntity/Citation``s on the message. The chat shows them as one quiet line under the answer rather than as
links through the text; tapping it lists them, and a web source opens in a Safari view without leaving the
conversation.

@Row {
    @Column {
        @Image(source: "Citations", alt: "Screenshot showing an answer followed by the web pages and the file it drew on.") {
            The sources of an answer sit under it, web pages and files alike, and open on a tap.
        }
    }
}

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

@Row {
    @Column {
        @Image(source: "ToolCall", alt: "Screenshot showing the assistant calling a tool to read health samples before answering.") {
            A tool call and its result are folded into the conversation above the answer they led to.
        }
    }
}

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
