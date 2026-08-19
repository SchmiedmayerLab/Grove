//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreGraphics
import Foundation
import FoundationModels
import GroveLLM
import ImageIO


/// One turn's worth of input, in the shape `FoundationModels` expects it.
///
/// `FoundationModels` splits a conversation in two — the transcript the model has already seen, and the prompt it is
/// being asked to answer — where `LLMContext` keeps a single flat list. This is that split.
@available(iOS 27, macOS 27, visionOS 27, *)
struct FoundationModelsRequest {
    /// The instructions and everything the model has already seen.
    let transcript: Transcript
    /// The turn to answer.
    let prompt: Prompt


    /// Splits an `LLMContext` into the parts of a `FoundationModels` request.
    ///
    /// - Parameters:
    ///   - context: The conversation so far. Its trailing user message becomes the prompt.
    ///   - systemPrompt: An additional instruction from the schema, placed ahead of the context's system messages.
    ///   - includesImages: Whether image content is carried over. Models without the `vision` capability reject
    ///     attachments outright, so for those the images are dropped and only the text goes over.
    init(context: LLMContext, systemPrompt: String?, includesImages: Bool) {
        let instructions = ([systemPrompt].compactMap { $0 } + context.compactMap { $0.role == .system ? $0.content : nil })
            .filter { !$0.isEmpty }

        // An image travels as its own entity with no text of its own, so one turn can span several entities.
        // Runs of the same role are therefore one message, and the trailing user run is the turn to answer.
        let turns = Self.turns(in: context)
        let promptTurn = turns.last?.role == .user ? turns.last : nil
        let history = promptTurn == nil ? turns : turns.dropLast()

        var entries: [Transcript.Entry] = []
        if !instructions.isEmpty {
            entries.append(
                .instructions(
                    .init(segments: [.text(.init(content: instructions.joined(separator: "\n\n")))], toolDefinitions: [])
                )
            )
        }
        entries += history.map { turn in
            let segments = Self.segments(for: turn.entities, includesImages: includesImages)
            return switch turn.role {
            case .user: .prompt(.init(segments: segments))
            default: .response(.init(assetIDs: [], segments: segments))
            }
        }

        self.transcript = Transcript(entries: entries)
        self.prompt = Self.prompt(for: promptTurn?.entities ?? [], includesImages: includesImages)
    }

    /// The conversation, with each run of same-role entities collapsed into one turn.
    private static func turns(in context: LLMContext) -> [(role: LLMContextEntity.Role, entities: [LLMContextEntity])] {
        context
            .filter { $0.role == .user || $0.role == .assistant }
            .reduce(into: []) { turns, entity in
                if turns.last?.role == entity.role {
                    turns[turns.endIndex - 1].entities.append(entity)
                } else {
                    turns.append((role: entity.role, entities: [entity]))
                }
            }
    }

    /// The prompt for the turn being answered, carrying its images where the model can take them.
    private static func prompt(for entities: [LLMContextEntity], includesImages: Bool) -> Prompt {
        let text = entities.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n")
        #if compiler(>=6.4)
        let images = includesImages ? entities.compactMap(\.cgImage) : []
        return Prompt {
            images.map { Attachment($0) }
            text
        }
        #else
        return Prompt {
            text
        }
        #endif
    }

    /// The text — and, where the model can take them, the images — a turn's entities carry.
    private static func segments(for entities: [LLMContextEntity], includesImages: Bool) -> [Transcript.Segment] {
        var segments: [Transcript.Segment] = []
        #if compiler(>=6.4)
        if includesImages {
            segments += entities.compactMap(\.cgImage).map { .attachment(.init(content: .image(.init($0)))) }
        }
        #endif
        let text = entities.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n")
        if !text.isEmpty {
            segments.append(.text(.init(content: text)))
        }
        return segments
    }
}


@available(iOS 27, macOS 27, visionOS 27, *)
extension LLMContextEntity {
    /// The entity's image, decoded.
    ///
    /// Returns `nil` when the entity carries no image, or when the data behind it doesn't decode — a malformed
    /// attachment is not worth failing the whole turn over, so the text goes on its own.
    fileprivate var cgImage: CGImage? {
        guard let imageContent = _imageContent,
              let data = Data(base64Encoded: imageContent.base64Image),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
