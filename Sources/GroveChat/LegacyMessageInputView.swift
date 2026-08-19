//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveSpeechRecognizer
import SwiftUI


/// The pre-Liquid-Glass message composer, used on platforms that don't offer the glass material.
@available(iOS 18, macOS 15, watchOS 11, *)
struct LegacyMessageInputView: View {
    @Binding private var chat: Chat
    private let placeholder: LocalizedStringResource
    private let speechToText: Bool

    @State private var speechRecognizer = SpeechRecognizer()
    @State private var message: String = ""

    @Environment(\.chatAccentColor) private var chatAccentColor
    @Environment(\.chatGeneration) private var generation
    @Environment(\.colorScheme) private var colorScheme

    @FocusState<Bool>.Binding private var textFieldIsFocused: Bool

    private var canSend: Bool {
        guard generation?.isGenerating != true else {
            // A second message mid-answer either interleaves two responses or drops the first.
            return false
        }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(text: $message, axis: .vertical) {
                Text(placeholder)
            }
            .accessibilityLabel(Text("MESSAGE_INPUT_TEXTFIELD", bundle: .module))
            .focused($textFieldIsFocused)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }
            .onSubmit(send)
            if speechToText {
                microphoneButton
            }
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .accessibilityLabel(Text("SEND_MESSAGE", bundle: .module))
                .foregroundStyle(
                    canSend
                        ? AnyShapeStyle(ChatPalette(accent: chatAccentColor, colorScheme: colorScheme).accent)
                        : AnyShapeStyle(.tertiary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var microphoneButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: "mic.fill")
                .font(.title2)
                .accessibilityLabel(Text("MICROPHONE_BUTTON", bundle: .module))
                .foregroundStyle(speechRecognizer.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .frame(height: 33)
        }
        .buttonStyle(.plain)
    }

    /// - Parameters:
    ///   - chat: The chat that should be appended to.
    ///   - placeholder: Placeholder text that should be added in the input field.
    ///   - isFocused: Whether the input field is currently the first responder.
    ///   - speechToText: Enables speech-to-text (recognition) capabilities of the input field.
    init(
        _ chat: Binding<Chat>,
        placeholder: LocalizedStringResource? = nil, // swiftlint:disable:this function_default_parameter_at_end
        isFocused: FocusState<Bool>.Binding,
        speechToText: Bool = true
    ) {
        self._chat = chat
        self.placeholder = placeholder ?? LocalizedStringResource("Type Your Message…", bundle: .module)
        self._textFieldIsFocused = isFocused
        self.speechToText = speechToText
    }

    private func send() {
        guard canSend else {
            return
        }
        speechRecognizer.stop()
        chat.append(ChatEntity(role: .user, text: message.trimmingCharacters(in: .whitespacesAndNewlines)))
        message = ""
    }

    private func toggleDictation() {
        guard !speechRecognizer.isRecording else {
            speechRecognizer.stop()
            return
        }
        Task {
            // A failed or interrupted recognition simply ends dictation; the typed message is left untouched.
            do {
                for try await result in speechRecognizer.start() {
                    message = result.bestTranscription.formattedString
                }
            } catch {
                speechRecognizer.stop()
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @Previewable @State var chat: Chat = [ChatEntity(role: .assistant(.response), text: "Assistant Message!")]
    @Previewable @FocusState var isFocused: Bool

    VStack {
        MessagesView($chat)
        LegacyMessageInputView($chat, isFocused: $isFocused)
    }
}
#endif
