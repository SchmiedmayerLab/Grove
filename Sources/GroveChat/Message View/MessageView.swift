//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import GroveSpeechSynthesizer
import GroveViews
public import SwiftUI


/// Displays a ``ChatEntity``, selecting the correct style based on its ``ChatEntity/role-swift.property``.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MessageView: View {
    /// The minimum inset a text message keeps from the edge it is not aligned to.
    private static let minHorizontalOpposingEdgeInset: Double = 48

    private let message: ChatEntity
    /// Whether the message closes its sender's run, which is what earns its bubble the tail.
    private let endsSenderRun: Bool

    /// Images want the room, so they give up most of the inset — an assistant image runs the full content width,
    /// the way ChatGPT lays generated images out, and a user's photo fills a correspondingly wider bubble.
    private var opposingEdgeInset: Double {
        guard !message.content.images.isEmpty else {
            return Self.minHorizontalOpposingEdgeInset
        }
        return message.alignment == .leading ? 0 : 24
    }

    var body: some View {
        HStack(spacing: 0) {
            if message.alignment == .trailing {
                Spacer(minLength: opposingEdgeInset)
            }
            VStack(alignment: message.horziontalAlignment, spacing: 0) {
                switch message.role {
                case .user:
                    PlainMessageView(message, insideBubble: true)
                        .chatMessageStyle(alignment: .trailing, tail: endsSenderRun)
                case .assistant(.response), .hidden:
                    AssistantMessageView(message)
                case .assistant(.thinking):
                    AssistantThinkingView(message)
                case .assistant(.toolCall), .assistant(.toolResponse):
                    ToolInteractionView(entity: message)
                }
            }
            if message.alignment == .leading {
                Spacer(minLength: opposingEdgeInset)
            }
        }
    }

    init(_ message: ChatEntity, endsSenderRun: Bool = true) {
        self.message = message
        self.endsSenderRun = endsSenderRun
    }
}


/// Displays an assistant-generated message, alongside the actions that can be taken on it.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct AssistantMessageView: View {
    private let message: ChatEntity

    @Environment(\.chatMessageActions) private var enabledActions
    @Environment(\.chatMessageActionsPresentation) private var presentation
    @State private var shareSheetInput: ShareSheetInput?
    @State private var didCopy = false
    // periphery:ignore - read through its projected value by SpeakMessageButton
    /// Held here rather than in the button: a context menu tears its own content down as it closes, taking any
    /// state the button owned — and with it the ability to stop what the tap started.
    @State private var isSpeaking = false

    /// Actions apply to a finished message; half a message is not worth copying or reading aloud.
    private var offersActions: Bool {
        // The follow-up lives on the text selection's own menu, so it alone puts no menu on the message.
        !enabledActions.subtracting(.followUp).isEmpty && message.complete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            messageContent
            if !message.citations.isEmpty && message.complete {
                SourcesView(citations: message.citations)
                    .transition(.opacity)
            }
            if offersActions && presentation == .inline {
                inlineActions
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.smooth(duration: 0.25), value: message.complete)
        // Presented from here rather than from the button: a context menu takes its own content away as it
        // closes, and a sheet anchored to a view that no longer exists never appears.
        .shareSheet(item: $shareSheetInput)
    }

    @ViewBuilder private var messageContent: some View {
        let content = PlainMessageView(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            // Selection is enabled where the message is rendered: with Textual the markup is composed into
            // views that only its own modifier reaches, and without it a plain `Text` takes SwiftUI's.
            .modifier(SelectableMessageText())
        if offersActions && presentation == .contextMenu {
            content.contextMenu {
                actionButtons
            }
        } else {
            content
        }
    }

    /// The actions themselves, laid out by whoever presents them.
    @ViewBuilder private var actionButtons: some View {
        if enabledActions.contains(.copy) && message.content.canTransfer {
            action(
                didCopy ? LocalizedStringResource("Copied", bundle: .module) : LocalizedStringResource("Copy", bundle: .module),
                symbolName: didCopy ? "checkmark" : "document.on.document"
            ) {
                message.content.copyToPasteboard()
                withAnimation(.smooth(duration: 0.2)) {
                    didCopy = true
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .task(id: didCopy) {
                guard didCopy else {
                    return
                }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.smooth(duration: 0.2)) {
                    didCopy = false
                }
            }
        }
        if enabledActions.contains(.speak) {
            SpeakMessageButton(message: message, isSpeaking: $isSpeaking)
        }
        if enabledActions.contains(.share), let text = message.content.text, !text.isEmpty {
            action(LocalizedStringResource("Share", bundle: .module), symbolName: "square.and.arrow.up") {
                shareSheetInput = .init(text)
            }
        }
    }

    private var inlineActions: some View {
        HStack(spacing: 18) {
            actionButtons
        }
        .labelStyle(.iconOnly)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, 2)
    }

    init(_ message: ChatEntity) {
        self.message = message
    }

    private func action(
        _ title: LocalizedStringResource,
        symbolName: String,
        _ action: @escaping @MainActor () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbolName)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }
}


/// Speaks an assistant message aloud, and stops the playback when tapped again.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct SpeakMessageButton: View {
    let message: ChatEntity
    @Binding var isSpeaking: Bool

    @Environment(SpeechSynthesizer.self) private var speechSynthesizer: SpeechSynthesizer?

    var body: some View {
        if let speechSynthesizer, let text = message.content.text, !text.isEmpty {
            Button {
                if isSpeaking {
                    speechSynthesizer.stop()
                } else {
                    speechSynthesizer.speak(text)
                }
                isSpeaking.toggle()
            } label: {
                Label {
                    Text("Speak", bundle: .module)
                } icon: {
                    Image(systemName: isSpeaking ? "speaker.slash" : "speaker.wave.2")
                }
            }
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))
            .contentShape(.rect)
            .onChange(of: speechSynthesizer.isSpeaking) { _, newValue in
                if !newValue {
                    isSpeaking = false
                }
            }
        }
    }
}


/// The actions that can be offered underneath an assistant message.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ChatMessageActions: OptionSet, Hashable, Sendable {
    /// Copies the message to the pasteboard.
    public static let copy = Self(rawValue: 1 << 0)
    /// Reads the message aloud. Requires a `SpeechSynthesizer` in the environment.
    public static let speak = Self(rawValue: 1 << 1)
    /// Offers the message to the system share sheet.
    public static let share = Self(rawValue: 1 << 2)
    /// Offers to quote the selected passage in the composer, from the text selection's own menu. Needs Textual.
    public static let followUp = Self(rawValue: 1 << 3)

    /// Every action.
    public static let all: Self = [.copy, .speak, .share, .followUp]

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}


/// How a message's actions are reached.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum ChatMessageActionsPresentation: Hashable, Sendable {
    /// Through a long press on the message, the way Messages and Mail present per-item actions.
    ///
    /// Costs the conversation nothing until the user asks for it, which is why it is the default. The long
    /// press is also the gesture that starts a text selection, so a chat that relies on selecting passages
    /// should present its actions ``inline`` instead.
    case contextMenu
    /// As a row of buttons underneath every completed assistant message.
    ///
    /// Always visible, and so always competing with the message it belongs to — suited to a general-purpose
    /// assistant more than to a focused, task-specific chat.
    case inline
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// The actions offered on assistant messages.
    @Entry var chatMessageActions: ChatMessageActions = .all
    /// How those actions are reached.
    @Entry var chatMessageActionsPresentation: ChatMessageActionsPresentation = .contextMenu
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Offers the given actions on every assistant message.
    ///
    /// Every action is offered through a long press by default, which keeps the conversation clear until the user
    /// asks for something. Pass `.inline` to lay the actions out under each message instead, or `[]` to offer none.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatMessageActions([.copy, .share], presentation: .inline)
    /// ```
    ///
    /// - Parameters:
    ///   - actions: The actions to offer. Defaults to all of them.
    ///   - presentation: How the actions are reached. Defaults to a long press.
    public func chatMessageActions(
        _ actions: ChatMessageActions,
        presentation: ChatMessageActionsPresentation = .contextMenu
    ) -> some View {
        environment(\.chatMessageActions, actions)
            .environment(\.chatMessageActionsPresentation, presentation)
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            MessageView(ChatEntity(role: .user, text: "Tell me a joke"))
            MessageView(ChatEntity(role: .assistant(.response), text: """
            Why do programmers prefer dark mode?

            Because light attracts bugs.
            """))
            MessageView(ChatEntity(role: .user, text: "A considerably longer user message, so that we can see how the bubble wraps."))
        }
        .padding()
    }
}
#endif
