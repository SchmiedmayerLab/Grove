//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
private import Combine
#endif
private import GroveFoundation
public import SwiftUI


/// Displays a ``Chat`` containing multiple ``ChatEntity``s with different ``ChatEntity/Role-swift.enum``s in a typical chat-like fashion.
///
/// The `View` automatically scrolls down to the newest message that is added to the passed ``Chat`` SwiftUI `Binding`.
/// Depending on the configured ``MessagesView/MessagesVisibility``, ``ChatEntity``s with certain roles are hidden from the `View`.
///
/// ### Usage
///
/// ```swift
/// struct MessagesViewTestView: View {
///     @State private var chat: Chat = [
///         ChatEntity(role: .user, text: "User Message!"),
///         ChatEntity(role: .assistant(.response), text: "Assistant Message!")
///     ]
///
///     var body: some View {
///         MessagesView($chat)
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Initializers
/// - ``init(_:insets:messagesVisibility:typingIndicator:)-(Binding<Chat>,_,_,_)``
/// - ``init(_:insets:messagesVisibility:typingIndicator:)-(Chat,_,_,_)``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct MessagesView: View {
    /// Specifies when to display an animation indicating a pending message from a chat participant.
    public enum TypingIndicatorDisplayMode: Hashable, Sendable {
        /// The animation is shown whenever the last message in the chat is from the user, and the assistant has not yet begun to respond.
        case automatic
        /// The animation is displayed based on the provided Boolean flag.
        case manual(shouldDisplay: Bool)
    }

    /// Configures which kinds of ``ChatEntity`` are surfaced to the user.
    public struct MessagesVisibility: Hashable, Sendable {
        /// Indicates which types of ``ChatEntity/Role-swift.enum/hidden(type:)`` message roles should be hidden from the chat.
        public enum HiddenMessages: Hashable, Sendable {
            /// Hide all messages with a `hidden` role, regardless of the message's ``ChatEntity/HiddenMessageType``.
            case all
            /// Displays all hidden messages, except some, based on their ``ChatEntity/HiddenMessageType``.
            case custom(Set<ChatEntity.HiddenMessageType>)

            /// No messages should be hidden.
            public static var none: Self {
                .custom([])
            }
        }

        /// Hides the messages a chat marks hidden, and shows everything the assistant actually did.
        ///
        /// Tool calls stay visible because that is what a chat showed before this type existed; an app that wants
        /// the tidier transcript asks for `toolCalls: .hidden` rather than being given it silently.
        public static var `default`: Self {
            .init(hiddenMessages: .all, toolCalls: .visible)
        }

        let hiddenMessages: HiddenMessages
        let toolCalls: Visibility
        let thinking: Visibility

        /// Creates a new visibility configuration.
        ///
        /// - Parameters:
        ///   - hiddenMessages: Which ``ChatEntity/Role-swift.enum/hidden(type:)`` messages to hide.
        ///   - toolCalls: Whether tool calls and their responses are shown.
        ///   - thinking: Whether the model's thinking phases are shown.
        public init(
            hiddenMessages: HiddenMessages,
            toolCalls: Visibility = .automatic,
            thinking: Visibility = .automatic
        ) {
            self.hiddenMessages = hiddenMessages
            self.toolCalls = toolCalls
            self.thinking = thinking
        }

        /// Whether a message is kept out of the conversation.
        ///
        /// - Parameters:
        ///   - message: The message about to be laid out.
        ///   - namedAsHidden: Messages the caller named through `View/chatHiddenMessages(_:)`. Those are
        ///     hidden whatever role they carry, because only the caller knows which of its own input is internal.
        func hides(_ message: ChatEntity, namedAsHidden: Set<UUID> = []) -> Bool {
            if namedAsHidden.contains(message.id) {
                return true
            }
            return switch message.role {
            case .user, .assistant(.response):
                false
            case .assistant(.toolCall), .assistant(.toolResponse):
                toolCalls == .hidden
            case .assistant(.thinking):
                thinking == .hidden
            case .hidden(let type):
                switch hiddenMessages {
                case .all:
                    true
                case .custom(let hiddenMessageTypes):
                    hiddenMessageTypes.contains(type)
                }
            }
        }
    }


    /// How close (in points) to the bottom edge the user must be for the view to keep following new content.
    private static let followContentThreshold: CGFloat = 64
    /// How far the typing indicator sits from the top when it is the only thing in the conversation.
    private static let emptyConversationIndicatorInset: CGFloat = 16

    @Binding private var chat: Chat
    private let insets: EdgeInsets
    private let messagesVisibility: MessagesVisibility
    private let typingIndicator: TypingIndicatorDisplayMode?

    /// Whether the user is pinned (near) the bottom of the conversation.
    ///
    /// While pinned, the view follows streaming content; once the user scrolls up to read, it stops yanking
    /// them back down and only resumes following when they return to the bottom or send a message themselves.
    @State private var isNearBottom = true
    /// Whether the conversation already had messages when the view appeared; only then does it open at the newest
    /// one. A first answer arriving into an empty view would otherwise land the reader at its end.
    @State private var opensAtNewestMessage = false
    @State private var hasAppeared = false
    /// Whether the user is dragging the conversation, which is the only thing that stops it following.
    @State private var isScrolling = false
    @State private var scrollPosition = ScrollPosition()
    @Environment(\.chatHiddenMessages) private var hiddenMessages
    @Environment(\.chatEmptyState) private var emptyState
    @Environment(\.chatErrorState) private var errorState
    @Environment(\.chatGeneration) private var generation

    private var visibleMessages: [ChatEntity] {
        chat.filter { !messagesVisibility.hides($0, namedAsHidden: hiddenMessages) }
    }

    private var shouldDisplayTypingIndicator: Bool {
        // A chat that reports its generation state has already answered this question, and answers it better:
        // the indicator then tracks the request itself rather than guessing from who spoke last — which would
        // leave it spinning after a cancelled answer, since the user's message is still the most recent one.
        if let generation {
            return generation.isGenerating
        }
        return switch typingIndicator {
        case .automatic:
            switch chat.last?.role {
            case .user:
                true
            // Ensure that the typing indicator is not shown when the chat only contains hidden messages.
            case .hidden:
                chat.contains { $0.role == .user || $0.role == .assistant(.response) }
            default:
                false
            }
        case .manual(let shouldDisplay):
            shouldDisplay
        case .none:
            false
        }
    }

    private var messageStack: some View {
        let messages = visibleMessages
        // A conversation is small enough to lay out eagerly, and a lazily materialized first row can
        // miss its appear events entirely — leaving a streamed answer parsed but never rendered.
        return VStack(spacing: 24) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                // Only the last message of a sender's run carries the bubble's tail, the way Messages
                // marks where a turn ends.
                MessageView(message, endsSenderRun: messages[safe: index + 1]?.role != message.role)
                    .id(message.id)
            }
            if shouldDisplayTypingIndicator {
                TypingIndicator()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // With no messages above it the indicator sits against the navigation bar, which reads as
                    // part of the chrome rather than as the answer being written.
                    .padding(.top, messages.isEmpty ? Self.emptyConversationIndicatorInset : 0)
            }
            ChatErrorView(state: errorState)
        }
    }

    /// Fills the conversation's space while it has nothing to show.
    @ViewBuilder private var emptyStateView: some View {
        if let content = emptyState.content, visibleMessages.isEmpty, !shouldDisplayTypingIndicator, errorState.error == nil {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    public var body: some View {
        conversation
    }

    /// The conversation itself, plus everything that decides where it is scrolled to.
    private var conversation: some View {
        ScrollView {
            messageStack
                .padding(.horizontal)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .scrollTargetLayout()
        }
        .overlay {
            emptyStateView
        }
        #if !os(visionOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        // A short conversation reads from the top; a longer one that is reopened starts at its newest message.
        // Growth is followed explicitly below, so scrolling up to read is not undone by the next token.
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(opensAtNewestMessage ? .bottom : .top, for: .initialOffset)
        .onAppear {
            guard !hasAppeared else {
                return
            }
            hasAppeared = true
            opensAtNewestMessage = !visibleMessages.isEmpty
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY < Self.followContentThreshold
        } action: { _, newValue in
            // An answer streaming in grows the content faster than a scroll can follow it, which would
            // otherwise read as the user having scrolled away and stop the view following at all.
            if newValue || isScrolling {
                isNearBottom = newValue
            }
        }
        .onScrollPhaseChange { _, newPhase in
            isScrolling = newPhase.isScrolling
        }
        .onChange(of: chat) { oldValue, newValue in
            if newValue.count > oldValue.count && newValue.last?.role == .user {
                // The user just sent a message; always bring it into view.
                scrollToBottom()
            } else if isNearBottom && Self.answerIsStreaming(from: oldValue, to: newValue) {
                // Follow streaming content only while the user hasn't scrolled away to read.
                scrollToBottom(animated: newValue.count != oldValue.count)
            }
        }
        #if os(iOS)
        .onReceive(keyboardWillShowPublisher) { _ in
            if isNearBottom {
                scrollToBottom()
            }
        }
        #endif
    }

    #if os(iOS)
    /// Fires shortly after the keyboard starts appearing, once the adjusted safe area has settled.
    private var keyboardWillShowPublisher: AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .map { _ in () }
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
    #endif


    /// Creates a `MessagesView` displaying an interactive conversation flow.
    ///
    /// - Parameters:
    ///   - chat: The chat messages that should be displayed.
    ///   - insets: `EdgeInsets` that should be applied within the view.
    ///   - messagesVisibility: Which kinds of messages should be surfaced to the user.
    ///   - typingIndicator: Whether a "three dots" animation should be automatically or manually shown; the default of `nil` results in no indicator being shown.
    public init(
        _ chat: Binding<Chat>,
        insets: EdgeInsets = EdgeInsets(),
        messagesVisibility: MessagesVisibility = .default,
        typingIndicator: TypingIndicatorDisplayMode? = nil
    ) {
        self._chat = chat
        self.insets = insets
        self.messagesVisibility = messagesVisibility
        self.typingIndicator = typingIndicator
    }

    /// Creates a `MessagesView` displaying a static conversation flow.
    ///
    /// - Parameters:
    ///   - chat: The chat messages that should be displayed.
    ///   - insets: `EdgeInsets` that should be applied within the view.
    ///   - messagesVisibility: Which kinds of messages should be surfaced to the user.
    ///   - typingIndicator: Whether a "three dots" animation should be automatically or manually shown; the default of `nil` results in no indicator being shown.
    public init(
        _ chat: Chat,
        insets: EdgeInsets = EdgeInsets(),
        messagesVisibility: MessagesVisibility = .default,
        typingIndicator: TypingIndicatorDisplayMode? = nil
    ) {
        self.init(.constant(chat), insets: insets, messagesVisibility: messagesVisibility, typingIndicator: typingIndicator)
    }

    /// Whether the answer arrived a piece at a time, rather than all at once.
    ///
    /// An answer that streams grows a message the view is already showing, and following it keeps the newest
    /// words in sight. One that lands whole — a provider without streaming, or the fallback after a stream
    /// fails — would otherwise drop the reader at the end of a page they have not read, and every answer would
    /// start with a scroll back up to its first line.
    private static func answerIsStreaming(from previous: Chat, to current: Chat) -> Bool {
        guard let last = current.last, last.role != .user else {
            return false
        }
        guard let previousLast = previous.last, previousLast.id == last.id else {
            // A message the view has not shown before: it is only being streamed if it arrived unfinished.
            return !last.complete
        }
        // A finished message that changes again — a citation attached, say — is not being streamed either.
        return !previousLast.complete
    }

    /// Scrolls to the foot of the conversation, where a drag would come to rest.
    ///
    /// Scrolling to the edge rather than to a view of our own at the end of the stack: an anchor view is
    /// positioned without regard for the scroll view's content insets, so following an answer left the
    /// conversation somewhere a participant could not have dragged it to.
    private func scrollToBottom(animated: Bool = true) {
        guard animated else {
            scrollPosition.scrollTo(edge: .bottom)
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview("Regular Message View") {
    MessagesView([
        ChatEntity(role: .user, text: "Tell me a joke"),
        ChatEntity(role: .hidden(type: .unknown), text: "Hidden Message!"),
        ChatEntity(role: .assistant(.response), text: "Why do programmers prefer dark mode?\n\nBecause light attracts bugs.")
    ])
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview("Unhidden Message View") {
    MessagesView(
        [
            ChatEntity(role: .user, text: "What's the weather?"),
            ChatEntity(role: .hidden(type: .unknown), text: "Hidden Message (but still visible)!"),
            ChatEntity(role: .assistant(.toolCall), text: "get_weather(location: \"Stanford\")"),
            ChatEntity(role: .assistant(.toolResponse), text: "{\n  \"temperature\": 21\n}"),
            ChatEntity(role: .assistant(.response), text: "It's 21 °C in Stanford.")
        ],
        messagesVisibility: .init(hiddenMessages: .none, toolCalls: .visible)
    )
}
#endif
