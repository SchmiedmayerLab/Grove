//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveSpeechRecognizer
import GroveViews
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif


/// A reusable SwiftUI `View` to handle text-, image-, or speech-based user input.
///
/// The composed message is appended to the passed ``Chat`` via a SwiftUI `Binding`. Input can be typed, dictated via
/// [`GroveSpeech`](../GroveSpeech/GroveSpeech.docc/GroveSpeech.md), or accompanied by images picked from the photo library.
///
/// The view floats above the conversation on a Liquid Glass surface, and collapses to a single row whenever the
/// message fits on one line.
@available(iOS 26, macOS 26, visionOS 26, *)
struct MessageInputView: View {
    typealias Attachment = DraftAttachment

    nonisolated static let cornerRadius: CGFloat = 22
    /// The side length of the circular controls flanking the field, matching its collapsed height.
    nonisolated static let controlSize: CGFloat = 40

    @Binding var chat: Chat
    private let placeholder: LocalizedStringResource
    let speechToText: Bool

    @State var speechRecognizer = SpeechRecognizer()
    @State var message: String = ""
    /// A passage of an earlier message the participant is asking about, staged until the message goes.
    @State var quotation: String?
    @State var attachments: [Attachment] = []
    /// What was written before dictation began, to fall back to if it is cancelled.
    @State var dictationBase = ""
    @State var dictationStart: Date?
    /// The voice as heard so far, for the waveform.
    @State var dictationLevels: [Float] = []
    /// Why the last picked file was refused, shown until the next pick.
    @State var attachmentFailure: String?
    #if canImport(PhotosUI)
    @State var photoSelection: [PhotosPickerItem] = []
    @State var attachmentLoadTask: Task<Void, Never>?
    @State var isShowingPhotoPicker = false
    @State var isShowingFileImporter = false
    @State var isShowingCamera = false
    #endif

    @Environment(\.chatAccentColor) private var chatAccentColor
    @Environment(\.chatAttachmentKinds) var attachmentKinds
    @Environment(\.chatGeneration) var generation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @Environment(ChatMessageQueue.self) var queue
    @Environment(ChatAttachmentStore.self) var attachmentStore: ChatAttachmentStore?

    @FocusState<Bool>.Binding var textFieldIsFocused: Bool

    private var palette: ChatPalette {
        ChatPalette(accent: chatAccentColor, colorScheme: colorScheme)
    }

    var isGenerating: Bool {
        generation?.isGenerating == true
    }

    /// Whether there is anything to send; mid-answer it is queued rather than sent.
    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || quotation != nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                queuedMessages
                if speechToText && speechRecognizer.isRecording {
                    dictationRow
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        leadingAction
                        inputField
                        trailingAction
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .onChange(of: speechRecognizer.level) { _, level in
            dictationLevels.append(level)
            if dictationLevels.count > 120 {
                dictationLevels.removeFirst(dictationLevels.count - 120)
            }
        }
        .animation(.smooth(duration: 0.3), value: attachments.count)
        .animation(.smooth(duration: 0.3), value: queue.messages.map(\.id))
        .onChange(of: queue.messageToEdit?.id) { _, id in
            if id != nil, let message = queue.messageToEdit {
                queue.messageToEdit = nil
                edit(message)
            }
        }
        .animation(.smooth(duration: 0.2), value: canSend)
        .animation(.smooth(duration: 0.2), value: speechRecognizer.isRecording)
        .animation(.smooth(duration: 0.2), value: generation?.isGenerating)
        .onChange(of: generation?.isGenerating) { _, generating in
            if generating == false {
                sendNextQueued()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        #if os(iOS) || os(visionOS)
        .background {
            // Blur out the scroll view content passing behind and below the composer.
            ProgressiveBlur(locations: [0, 0.55])
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        #endif
        #if canImport(PhotosUI) && !os(watchOS)
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, selection in
            loadAttachments(from: selection)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: ChatAttachmentStore.defaultContentTypes,
            allowsMultipleSelection: true
        ) { result in
            stageFiles(from: result)
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                attachments.append(Attachment(itemIdentifier: nil, content: .image(image)))
            }
            .ignoresSafeArea()
        }
        #endif
    }

    /// The field itself, which carries whatever the user has staged for the next message.
    private var inputField: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Also shown for a refusal with nothing staged: a file that was rejected has to say so, and refusing
            // the only file picked would otherwise leave the composer looking as if nothing had happened.
            if !attachments.isEmpty || attachmentFailure != nil {
                attachmentPreviews
            }
            if quotation != nil {
                quotationPreview
            }
            TextField(text: $message, axis: .vertical) {
                Text(placeholder)
            }
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .accessibilityLabel(Text("MESSAGE_INPUT_TEXTFIELD", bundle: .module))
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($textFieldIsFocused)
            .onSubmit(send)
            .modifier(QuotationPickup(quotation: $quotation, isFocused: $textFieldIsFocused))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: Self.controlSize)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        // The whole field behaves as one big button that focuses the text, wherever it is tapped.
        .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture {
            textFieldIsFocused = true
        }
    }

    /// Dictation while the field is empty, sending once there is something to send; while an answer that can be
    /// stopped arrives, the stop button gets the send button beside it once there is something to queue.
    @ViewBuilder private var trailingAction: some View {
        if isGenerating, generation?.cancel != nil {
            stopButton
            if canSend {
                sendButton
            }
        } else if canSend || !speechToText {
            sendButton
        } else {
            microphoneButton
        }
    }

    /// Interrupts the answer in flight.
    private var stopButton: some View {
        Button {
            generation?.cancel?()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 14, weight: .bold))
                .accessibilityLabel(Text("STOP_GENERATING", bundle: .module))
                .foregroundStyle(palette.onAccent)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(palette.accent, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .accessibilityLabel(Text(LocalizedStringKey(isGenerating ? "QUEUE_MESSAGE" : "SEND_MESSAGE"), bundle: .module))
                .foregroundStyle(canSend ? AnyShapeStyle(palette.onAccent) : AnyShapeStyle(.secondary))
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(canSend ? AnyShapeStyle(palette.accent) : AnyShapeStyle(.quaternary), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var microphoneButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .accessibilityLabel(Text("MICROPHONE_BUTTON", bundle: .module))
                .foregroundStyle(.secondary)
                .frame(width: Self.controlSize, height: Self.controlSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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

    #if canImport(PhotosUI) && !os(watchOS)
    private func loadAttachments(from selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else {
            return
        }
        // Selections arrive cumulatively while the picker stays open; each change supersedes the load before it.
        attachmentLoadTask?.cancel()
        attachmentLoadTask = Task {
            var loaded: [Attachment] = []
            for item in selection {
                guard !Task.isCancelled else {
                    return
                }
                if let data = try? await item.loadTransferable(type: Data.self), let image = PlatformImage(data: data) {
                    loaded.append(Attachment(itemIdentifier: item.itemIdentifier, content: .image(image)))
                }
            }
            let newAttachments = loaded
            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }
                // Deduplicate against what an earlier, already-landed load staged from an overlapping selection.
                let fresh = newAttachments.filter { attachment in
                    attachment.itemIdentifier == nil
                        || !attachments.contains { $0.itemIdentifier == attachment.itemIdentifier }
                }
                withAnimation(.smooth(duration: 0.3)) {
                    attachments.append(contentsOf: fresh)
                }
                photoSelection = []
            }
        }
    }
    #endif
}

#if DEBUG
@available(iOS 26, macOS 26, visionOS 26, *)
#Preview {
    @Previewable @State var chat: Chat = [
        ChatEntity(role: .user, text: "Tell me a joke"),
        ChatEntity(role: .assistant(.response), text: "Why do programmers prefer dark mode?\n\nBecause light attracts bugs.")
    ]
    @Previewable @FocusState var isFocused: Bool

    NavigationStack {
        MessagesView($chat)
            .safeAreaInset(edge: .bottom) {
                MessageInputView($chat, isFocused: $isFocused)
            }
    }
}
#endif
