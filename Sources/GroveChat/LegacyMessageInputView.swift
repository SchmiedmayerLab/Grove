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
    /// A passage of an earlier message the participant is asking about, staged until the message goes.
    @State private var quotation: String?
    /// What was written before dictation began, to fall back to if it is cancelled.
    @State private var dictationBase = ""
    @State private var dictationStart: Date?
    /// The voice as heard so far, for the waveform.
    @State private var dictationLevels: [Float] = []

    @Environment(\.chatAccentColor) private var chatAccentColor
    @Environment(\.chatGeneration) private var generation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(ChatMessageQueue.self) private var queue

    @FocusState<Bool>.Binding private var textFieldIsFocused: Bool

    private var isGenerating: Bool {
        generation?.isGenerating == true
    }

    /// Whether there is anything to send; mid-answer it is queued rather than sent.
    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || quotation != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !queue.isExpanded {
                QueuedMessageStack(
                    messages: queue.messages,
                    cornerRadius: 14,
                    edit: edit,
                    fanOut: { queue.isExpanded = true },
                    removeAll: { queue.messages.removeAll() }
                ) { chip in
                    chip.background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let quotation {
                QuotationChip(text: quotation) {
                    withAnimation(.smooth(duration: 0.25)) {
                        self.quotation = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if speechToText && speechRecognizer.isRecording {
                dictationRow
            } else {
                inputRow
            }
        }
        .onChange(of: speechRecognizer.level) { _, level in
            dictationLevels.append(level)
            if dictationLevels.count > 120 {
                dictationLevels.removeFirst(dictationLevels.count - 120)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.smooth(duration: 0.3), value: queue.messages.map(\.id))
        .onChange(of: queue.messageToEdit?.id) { _, id in
            if id != nil, let message = queue.messageToEdit {
                queue.messageToEdit = nil
                edit(message)
            }
        }
        .onChange(of: generation?.isGenerating) { _, generating in
            if generating == false {
                sendNextQueued()
            }
        }
    }

    /// The field and the controls flanking it.
    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(text: $message, axis: .vertical) {
                Text(placeholder)
            }
            .accessibilityLabel(Text("MESSAGE_INPUT_TEXTFIELD", bundle: .module))
            .focused($textFieldIsFocused)
            .modifier(QuotationPickup(quotation: $quotation, isFocused: $textFieldIsFocused))
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
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .accessibilityLabel(Text(LocalizedStringKey(isGenerating ? "QUEUE_MESSAGE" : "SEND_MESSAGE"), bundle: .module))
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
                .foregroundStyle(.secondary)
                .frame(height: 33)
        }
        .buttonStyle(.plain)
    }

    /// The composer while it listens: a way out, the voice as heard with the time taken, and the stop that keeps it.
    private var dictationRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: cancelDictation) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .accessibilityLabel(Text("CANCEL_DICTATION", bundle: .module))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                DictationWaveform(levels: dictationLevels)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                if let dictationStart {
                    TimelineView(.periodic(from: dictationStart, by: 1)) { timeline in
                        Text(Duration.seconds(max(0, timeline.date.timeIntervalSince(dictationStart))), format: .time(pattern: .minuteSecond))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.thinMaterial, in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("RECORDING", bundle: .module))
            .accessibilityIdentifier("Recording")
            Button(action: speechRecognizer.stop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title)
                    .accessibilityLabel(Text("STOP_DICTATION", bundle: .module))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
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
        let draft = QueuedMessage(text: message.trimmingCharacters(in: .whitespacesAndNewlines), quotation: quotation, attachments: [])
        message = ""
        quotation = nil
        if isGenerating {
            queue.messages.append(draft)
        } else {
            chat.append(draft.entity)
        }
    }

    /// Lets the first queued message go, once the chat can take it; a closed composer keeps them.
    private func sendNextQueued() {
        guard isEnabled, !queue.messages.isEmpty else {
            return
        }
        chat.append(queue.messages.removeFirst().entity)
    }

    /// Takes a queued message back into the field, ahead of whatever is being written there.
    private func edit(_ queuedMessage: QueuedMessage) {
        queue.messages.removeAll { $0.id == queuedMessage.id }
        message = [queuedMessage.text, message].filter { !$0.isEmpty }.joined(separator: "\n")
        quotation = queuedMessage.quotation ?? quotation
        textFieldIsFocused = true
    }

    private func toggleDictation() {
        guard !speechRecognizer.isRecording else {
            speechRecognizer.stop()
            return
        }
        // Dictation adds to what is written, so a message can be typed and spoken by turns.
        let written = message.trimmingCharacters(in: .whitespacesAndNewlines)
        dictationBase = written
        dictationLevels = []
        dictationStart = .now
        Task {
            // A failed or interrupted recognition simply ends dictation; the typed message is left untouched.
            do {
                for try await result in speechRecognizer.start() {
                    message = [written, result.bestTranscription.formattedString].filter { !$0.isEmpty }.joined(separator: " ")
                }
            } catch {
                speechRecognizer.stop()
            }
        }
    }

    /// Ends the recording and drops what it heard, leaving the message as it was written.
    private func cancelDictation() {
        speechRecognizer.stop()
        message = dictationBase
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
