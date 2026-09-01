//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(GroveChat)
import Foundation
public import GroveChat
private import GroveFoundation
import UniformTypeIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContext {
    /// Maps the ``LLMContext`` to a `GroveChat/Chat`.
    ///
    /// All ``LLMContextEntity/Role-swift.enum/assistantThinking`` entities belonging to the same interaction are folded
    /// into a single chat entity, so that a model that reasons repeatedly within one turn — e.g. around a tool call —
    /// still shows up as one "Thought for …" disclosure.
    public var chat: Chat {
        get {
            let bounds = interactionBounds()
            var thinkingAnchorIndices: [LLMInteractionId: Int] = [:]
            var result: Chat = []
            result.reserveCapacity(count)
            for entity in self {
                if case .assistantThinking = entity.role {
                    appendThinking(entity, to: &result, anchors: &thinkingAnchorIndices, bounds: bounds)
                } else if let chatEntity = entity.chatEntity {
                    result.append(chatEntity)
                }
            }
            return result
        }
        set {
            // Only newly added `user` messages are written back into the context; everything else in the `Chat`
            // is a projection of entities the session itself produced.
            guard let newEntity = newValue.last, case .user = newEntity.role, !contains(where: { $0.id == newEntity.id }) else {
                return
            }
            let images = newEntity.content.images
            let files = newEntity.content.files
            guard !images.isEmpty || !files.isEmpty else {
                append(userMessage: newEntity.content.text ?? "", id: newEntity.id, date: newEntity.date)
                return
            }
            appendUserMessage(
                images: images,
                files: files,
                text: newEntity.content.text,
                id: newEntity.id,
                date: newEntity.date
            )
        }
    }

    /// Writes a user message carrying images back into the context.
    ///
    /// Each in-memory image becomes its own entity with an inline JPEG payload — the representation the
    /// OpenAI-compatible request builders send to the model. Remote image URLs cannot be inlined synchronously
    /// (and the chat composer never produces them), so they are skipped here.
    ///
    /// The chat entity's id lands on the final appended entity, keeping the write-back idempotent and preserving
    /// "last message is a complete user message" as the generation trigger.
    private mutating func appendUserMessage(
        images: [ChatEntity.Content.Image],
        files: [ChatEntity.Content.File],
        text: String?,
        id: UUID,
        date: Date
    ) {
        let platformImages = images.compactMap { image -> LLMContextEntity._PlatformImage? in
            guard case .image(let platformImage) = image else {
                return nil
            }
            return platformImage
        }
        let text = text.flatMap { $0.isEmpty ? nil : $0 }
        // The chat entity's id has to land on whatever is appended last, so the write-back stays idempotent.
        let attachmentCount = platformImages.count + files.count
        for (index, platformImage) in platformImages.enumerated() {
            let carriesChatId = text == nil && index == attachmentCount - 1
            guard let entity = LLMContextEntity(
                _role: .user,
                image: platformImage,
                format: .jpeg(compressionFactor: 0.8),
                id: carriesChatId ? id : UUID(),
                date: date
            ) else {
                continue
            }
            append(entity)
        }
        for (index, file) in files.enumerated() {
            let carriesChatId = text == nil && platformImages.count + index == attachmentCount - 1
            guard let entity = LLMContextEntity(
                _role: .user,
                fileURL: file.url,
                contentType: file.mimeType,
                filename: file.name,
                id: carriesChatId ? id : UUID(),
                date: date
            ) else {
                continue
            }
            append(entity)
        }
        if let text {
            append(userMessage: text, id: id, date: date)
        }
    }

    /// The first and last moment seen for every interaction in the context.
    ///
    /// An entity's contribution to the upper bound is its ``LLMContextEntity/completionDate`` when it streamed in,
    /// so that a thinking phase's duration spans until its streaming actually ended — not just until it began.
    private func interactionBounds() -> [LLMInteractionId: ClosedRange<Date>] {
        var bounds: [LLMInteractionId: ClosedRange<Date>] = [:]
        for entity in self {
            guard let id = entity.interactionId else {
                continue
            }
            let lastSeen = entity.completionDate ?? entity.date
            if let existing = bounds[id] {
                bounds[id] = Swift.min(existing.lowerBound, entity.date)...Swift.max(existing.upperBound, lastSeen)
            } else {
                bounds[id] = entity.date...Swift.max(entity.date, lastSeen)
            }
        }
        return bounds
    }

    private func appendThinking(
        _ entity: LLMContextEntity,
        to result: inout Chat,
        anchors: inout [LLMInteractionId: Int],
        bounds: [LLMInteractionId: ClosedRange<Date>]
    ) {
        let range = entity.interactionId.flatMap { bounds[$0] }
        let role = ChatEntity.Role.assistant(.thinking(startDate: range?.lowerBound, endDate: range?.upperBound))
        guard let interactionId = entity.interactionId, let anchorIndex = anchors[interactionId] else {
            if let interactionId = entity.interactionId {
                anchors[interactionId] = result.count
            }
            result.append(ChatEntity(
                role: role,
                content: .text(entity.content),
                complete: entity.complete,
                id: entity.id,
                date: entity.date
            ))
            return
        }
        // Merge into the interaction's first thinking entity rather than adding a second disclosure.
        var anchor = result[anchorIndex]
        anchor.role = role
        anchor.content = .text([anchor.content.text, entity.content].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n\n"))
        anchor.complete = anchor.complete && entity.complete
        result[anchorIndex] = anchor
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMContextEntity {
    /// The entity's representation within a `GroveChat/Chat`, if it has one.
    fileprivate var chatEntity: ChatEntity? {
        let role: ChatEntity.Role? = switch self.role {
        case .user: .user
        case .assistant: .assistant(.response)
        case .toolCalls: .assistant(.toolCall)
        case .toolCallResponse: .assistant(.toolResponse)
        case .system: .hidden(type: .system)
        case .assistantThinking: nil
        }
        guard let role else {
            return nil
        }
        return ChatEntity(
            role: role,
            content: chatContent,
            complete: complete,
            citations: (citations ?? []).map(\.chatCitation),
            id: id,
            date: date
        )
    }

    /// The entity's content, in the chat's own model.
    ///
    /// Part identities are derived from the entity's, because this is recomputed every time the chat is read: a
    /// part that took a fresh identity each time would tell SwiftUI the message had been replaced on every token.
    private var chatContent: ChatEntity.Content {
        // Inline image payloads surface as data URLs, which the chat's image views load and decode lazily.
        if let imageContent = _imageContent,
           let url = URL(string: "data:\(imageContent.contentType);base64,\(imageContent.base64Image)") {
            var parts = [ChatEntity.Content.Part(.image(.url(url)), entityID: id, index: 0)]
            if !content.isEmpty {
                parts.append(ChatEntity.Content.Part(.text(content), entityID: id, index: 1))
            }
            return ChatEntity.Content(parts)
        }
        if let fileContent = _fileContent, let url = fileContent.url {
            let file = ChatEntity.Content.File(
                name: fileContent.filename,
                url: url,
                contentTypeIdentifier: fileContent.contentType.utType?.identifier
            )
            var parts = [ChatEntity.Content.Part(.file(file), entityID: id, index: 0)]
            if !content.isEmpty {
                parts.append(ChatEntity.Content.Part(.text(content), entityID: id, index: 1))
            }
            return ChatEntity.Content(parts)
        }
        let text = if case .toolCalls(let toolCalls) = role {
            toolCalls.map { "\($0.name)(\($0.arguments))" }.joined(separator: "\n")
        } else {
            content
        }
        return ChatEntity.Content([.init(.text(text), entityID: id, index: 0)])
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.File {
    /// The MIME type a request builder sends for this file.
    ///
    /// ``ChatEntity/Content/File/contentTypeIdentifier`` is a uniform type identifier so the chat model stays
    /// Foundation-only; the wire wants a MIME type, and an unrecognised kind travels as opaque bytes.
    fileprivate var mimeType: MIMEType {
        contentTypeIdentifier
            .flatMap(UTType.init)
            .flatMap(MIMEType.init)
            ?? .octetStream
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.HiddenMessageType {
    /// System hidden message type of the `ChatEntity`.
    static let system = ChatEntity.HiddenMessageType(name: "system")
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMCitation {
    /// The same citation, in the chat's own vocabulary.
    fileprivate var chatCitation: ChatEntity.Citation {
        let chatSource: ChatEntity.Citation.Source = switch source {
        case .web(let url): .web(url)
        case .file(let name): .file(name: name)
        }
        return ChatEntity.Citation(title: title, source: chatSource, id: id)
    }
}
#endif
