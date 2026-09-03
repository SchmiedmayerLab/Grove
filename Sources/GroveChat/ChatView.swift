//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveFoundation
public import SwiftUI


/// Provides a basic reusable chat view which includes a message input field. The input can be typed out via the keyboard,
/// dictated as voice input, or accompanied by images picked from the photo library.
///
/// The actual content of the ``ChatView`` is defined by a ``Chat``, which contains an ordered array of ``ChatEntity``s representing the individual messages within the ``ChatView``.
/// The ``Chat`` is passed to the ``ChatView`` as a SwiftUI `Binding`, which enables modification of the ``Chat`` from outside of the view, for example via a SwiftUI `.onChange()` `View` modifier.
///
/// ### Usage
///
/// A minimal example of the ``ChatView`` can be found below.
/// Ensure that the `ChatTestView` is wrapped within a SwiftUI `NavigationStack` in order to specify the `.navigationTitle()` view modifier.
///
/// ```swift
/// struct ChatTestView: View {
///     @State private var chat: Chat = [
///         ChatEntity(role: .assistant(.response), text: "Assistant Message!")
///     ]
///
///     var body: some View {
///         ChatView($chat)
///             .navigationTitle("GroveChat")
///     }
/// }
/// ```
///
/// ### Accessibility
///
/// The ``ChatView`` provides speech-to-text (recognition) as well as text-to-speech (synthesize) capabilities out of the box via the [`GroveSpeech`](../GroveSpeech/GroveSpeech.docc/GroveSpeech.md) module, facilitating seamless interaction with the content of the ``ChatView``.
///
/// Speech-to-text capabilities are enabled by default and can be configured via the `View/speechToText(_:)` modifier.
///
/// Text-to-speech capabilities can be configured via the `View/speak(_:muted:)` `ViewModifier`. If present, the latest ``ChatEntity/complete`` ``ChatEntity/Role-swift.enum/assistant(_:)`` message in the ``Chat`` will be synthesized to natural language speech.
/// In addition, the `View/speechToolbarButton(enabled:muted:)` `ViewModifier` automatically adds a toolbar `Button` to mute or unmute the speech synthesizer, if not disabled via the `enabled` parameter.
///
/// ```swift
/// struct ChatTestView: View {
///     @State private var chat: Chat = [
///         ChatEntity(role: .assistant(.response), text: "**Assistant** Message!")
///     ]
///     @State private var muted = false
///
///     var body: some View {
///         ChatView($chat)
///             // Output new completed `assistant` content within the `Chat` via speech
///             .speak(chat, muted: muted)
///             .speechToolbarButton(muted: $muted)
///     }
/// }
/// ```
///
/// ### Export of Chat
///
/// The ``ChatView`` provides functionality to export the visualized ``Chat`` as a PDF document, JSON representation, or textual UTF-8 file (see ``ChatView/ChatExportFormat``).
/// The export is enabled via an iOS-typical Share Sheet that is triggered by a click on the share `Button` in the `.toolbar()`.
///
/// ```swift
/// struct ChatExportTestView: View {
///     @State private var chat: Chat = [
///         // ...
///     ]
///
///     var body: some View {
///         ChatView($chat, exportFormat: .pdf)
///             .navigationTitle("GroveChat")
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ChatView: View {
    private enum ExportAvailability {
        /// The export functionality is wholly unavailable.
        case unavailable
        /// The export functionality is available, and might or might not be enabled.
        case available(enabled: Bool)
    }

    @Environment(\.chatViewInsets) private var insets
    @Environment(\.chatSpeechToTextEnabled) private var speechToText
    @Binding var chat: Chat
    private let disableInput: Bool
    let exportFormat: ChatExportFormat?
    private let messagePlaceholder: LocalizedStringResource?
    private let messagePendingAnimation: MessagesView.TypingIndicatorDisplayMode?
    private let messagesVisibility: MessagesView.MessagesVisibility

    @State private var showShareSheet = false
    @FocusState private var inputTextFieldIsFocused: Bool
    /// Carries a quoted message from the conversation to the composer, which are siblings here.
    @State private var followUp = ChatFollowUp()

    public var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom) {
                inputView
            }
            .toolbar {
                toolbar
            }
            .sheet(isPresented: $showShareSheet) {
                shareSheet
            }
            .environment(followUp)
            .modifier(SingleTextSelection())
            #if os(macOS)
            .onChange(of: showShareSheet) { _, isPresented in
                if isPresented, let exportFormat, let exportedData = Self.export(chat, as: exportFormat) {
                    ShareSheet(sharedItem: exportedData, sharedItemType: exportFormat).show()
                    showShareSheet = false
                }
            }
            // `NSSharingServicePicker` doesn't provide a completion handler as `UIActivityViewController` does,
            // therefore necessitating the deletion of the temporary file on disappearing.
            .onDisappear {
                if let exportFormat {
                    try? FileManager.default.removeItem(at: Self.temporaryExportFilePath(sharedItemType: exportFormat))
                }
            }
            #endif
    }

    private var messagesView: some View {
        MessagesView(
            $chat,
            insets: EdgeInsets(
                top: insets.top,
                leading: insets.leading,
                bottom: insets.bottom + 8,
                trailing: insets.trailing
            ),
            messagesVisibility: messagesVisibility,
            typingIndicator: messagePendingAnimation
        )
        #if !os(macOS)
        .onTapGesture {
            inputTextFieldIsFocused = false
        }
        #endif
    }

    @ViewBuilder private var inputView: some View {
        #if os(iOS) || os(visionOS)
        if #available(iOS 26, visionOS 26, *) {
            MessageInputView($chat, placeholder: messagePlaceholder, isFocused: $inputTextFieldIsFocused, speechToText: speechToText)
                .disabled(disableInput)
        } else {
            legacyInputView
        }
        #else
        legacyInputView
        #endif
    }

    private var legacyInputView: some View {
        LegacyMessageInputView($chat, placeholder: messagePlaceholder, isFocused: $inputTextFieldIsFocused, speechToText: speechToText)
            .disabled(disableInput)
    }

    @ViewBuilder private var shareSheet: some View {
        if let exportFormat, let exportedData = Self.export(chat, as: exportFormat) {
            #if !os(macOS)
            ShareSheet(sharedItem: exportedData, sharedItemType: exportFormat)
                .presentationDetents([.medium])
            #endif
        } else {
            ProgressView()
                .padding()
                .presentationDetents([.medium])
        }
    }

    private var exportAvailability: ExportAvailability {
        guard exportFormat != nil else {
            return .unavailable
        }
        // Only enable the export toolbar item if there are visible messages.
        return .available(enabled: chat.contains { $0.role == .assistant(.response) || $0.role == .user })
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if case let .available(enabled) = exportAvailability {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(Text("EXPORT_CHAT_BUTTON", bundle: .module))
                }
                .disabled(!enabled)
            }
        }
    }


    /// - Parameters:
    ///   - chat: The chat that should be displayed.
    ///   - disableInput: Flag if the input view should be disabled.
    ///   - exportFormat: If specified, enables the export of the ``Chat`` displayed in the ``ChatView`` via a share sheet in various formats defined in ``ChatView/ChatExportFormat``.
    ///   - messagePlaceholder: Placeholder text that should be added in the input field.
    ///   - messagePendingAnimation: Parameter to control whether a chat bubble animation is shown.
    ///   - messagesVisibility: Which kinds of messages should be surfaced to the user.
    public init(
        _ chat: Binding<Chat>,
        disableInput: Bool = false,
        exportFormat: ChatExportFormat? = nil,
        messagePlaceholder: LocalizedStringResource? = nil,
        messagePendingAnimation: MessagesView.TypingIndicatorDisplayMode? = nil,
        messagesVisibility: MessagesView.MessagesVisibility = .default
    ) {
        self._chat = chat
        self.disableInput = disableInput
        self.exportFormat = exportFormat
        self.messagePlaceholder = messagePlaceholder
        self.messagesVisibility = messagesVisibility
        self.messagePendingAnimation = messagePendingAnimation
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    @Entry fileprivate var chatViewInsets = EdgeInsets()
    @Entry fileprivate var chatSpeechToTextEnabled = true
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Enables or disables speech-to-text input in a ``ChatView``.
    ///
    /// Speech-to-text is enabled by default. Disable it when the app does not offer dictation or does not include
    /// the required speech-recognition usage descriptions.
    public func speechToText(_ enabled: Bool = true) -> some View {
        environment(\.chatSpeechToTextEnabled, enabled)
    }

    /// Specifies extra insets that should be added to a ``ChatView``.
    ///
    /// - Note: Prefer this modifier over applying a padding to the ``ChatView`` directly.
    ///     Directly applied padding will cause the `ChatView`'s inner `ScrollView` to no longer extend its contents below the
    ///     navigation bar or underneath the system keyboard. This modifier instead applies the insets within the `ScrollView`.
    public func chatViewInsets(_ insets: EdgeInsets) -> some View {
        transformEnvironment(\.chatViewInsets) { current in
            current.top += insets.top
            current.bottom += insets.bottom
            current.leading += insets.leading
            current.trailing += insets.trailing
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    NavigationStack {
        ChatView(
            .constant([
                ChatEntity(role: .user, text: "Tell me a joke"),
                ChatEntity(role: .hidden(type: .unknown), text: "Hidden Message!"),
                ChatEntity(role: .assistant(.response), text: "Why do programmers prefer dark mode?\n\nBecause light attracts bugs.")
            ]),
            exportFormat: .pdf
        )
        .navigationTitle("GroveChat")
    }
}
#endif
