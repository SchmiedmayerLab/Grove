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
    /// An image the user staged for the next message, with an identity of its own so that
    /// removal targets the right item even while insertions and removals animate.
    struct Attachment: Identifiable {
        /// What the user staged.
        enum Content {
            case image(PlatformImage)
            case file(ChatEntity.Content.File)
        }

        let id = UUID()
        /// The photo library identifier the image was loaded from, when it has one; guards against
        /// staging the same photo twice when picker selections overlap.
        let itemIdentifier: String?
        let content: Content
    }

    private static let cornerRadius: CGFloat = 22
    /// The side length of the circular controls flanking the field, matching its collapsed height.
    nonisolated static let controlSize: CGFloat = 40

    @Binding private var chat: Chat
    private let placeholder: LocalizedStringResource
    let speechToText: Bool

    @State private var speechRecognizer = SpeechRecognizer()
    @State private var message: String = ""
    @State var attachments: [Attachment] = []
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
    @Environment(\.chatGeneration) private var generation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ChatAttachmentStore.self) var attachmentStore: ChatAttachmentStore?

    @FocusState<Bool>.Binding private var textFieldIsFocused: Bool

    private var palette: ChatPalette {
        ChatPalette(accent: chatAccentColor, colorScheme: colorScheme)
    }

    private var canSend: Bool {
        guard generation?.isGenerating != true else {
            // A second message mid-answer either interleaves two responses or drops the first.
            return false
        }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                attachButton
                inputField
                trailingAction
            }
        }
        .animation(.smooth(duration: 0.3), value: attachments.count)
        .animation(.smooth(duration: 0.2), value: canSend)
        .animation(.smooth(duration: 0.2), value: speechRecognizer.isRecording)
        .animation(.smooth(duration: 0.2), value: generation?.isGenerating)
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
            TextField(text: $message, axis: .vertical) {
                Text(placeholder)
            }
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .accessibilityLabel(Text("MESSAGE_INPUT_TEXTFIELD", bundle: .module))
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($textFieldIsFocused)
            .onSubmit(send)
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

    /// Dictation while the field is empty, sending once there is something to send.
    ///
    /// Both stay up while dictating, so that a dictated message can be either stopped or sent straight away.
    @ViewBuilder private var trailingAction: some View {
        if generation?.isGenerating == true {
            stopButton
        } else if speechToText && speechRecognizer.isRecording {
            microphoneButton
            sendButton
        } else if canSend || !speechToText {
            sendButton
        } else {
            microphoneButton
        }
    }

    /// Interrupts the answer in flight, standing in for the send button until it finishes.
    @ViewBuilder private var stopButton: some View {
        if let cancel = generation?.cancel {
            Button {
                cancel()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityLabel(Text("STOP_GENERATING", bundle: .module))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: Self.controlSize, height: Self.controlSize)
                    .background(palette.accent, in: .circle)
            }
            .buttonStyle(.plain)
        } else {
            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .accessibilityLabel(Text("SEND_MESSAGE", bundle: .module))
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
            Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 16))
                .accessibilityLabel(Text("MICROPHONE_BUTTON", bundle: .module))
                .foregroundStyle(speechRecognizer.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .frame(width: Self.controlSize, height: Self.controlSize)
                .symbolEffect(.variableColor.iterative, isActive: speechRecognizer.isRecording)
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

    private func send() {
        guard canSend else {
            return
        }
        speechRecognizer.stop()
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = attachments.map { attachment in
            switch attachment.content {
            case .image(let image): ChatEntity.Content.Part(.image(.image(image)))
            case .file(let file): ChatEntity.Content.Part(.file(file), label: file.name)
            }
        }
        if !text.isEmpty {
            parts.append(ChatEntity.Content.Part(.text(text)))
        }
        let content = ChatEntity.Content(parts)
        chat.append(ChatEntity(role: .user, content: content))
        message = ""
        attachments = []
        #if canImport(PhotosUI)
        photoSelection = []
        #endif
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
