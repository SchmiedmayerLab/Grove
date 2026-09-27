//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLM


/// Assembles each assistant item's content independently of overlapping responses and content parts.
@available(iOS 18, macOS 15, watchOS 11, *)
struct RealtimeAssistantTranscripts: Sendable {
    private enum Change {
        case delta(String)
        case final(String)
    }

    private struct Part: Sendable {
        var content = ""
        var complete = false
    }

    private struct Response: Sendable {
        let interactionId: LLMInteractionId
        var items: [String: [Int: Part]] = [:]
    }

    private var responses: [String: Response] = [:]

    mutating func consume(_ event: LLMRealtimeAudioEvent, context: inout LLMContext) {
        switch event {
        case .responseCreated(let response):
            if responses[response.id] == nil {
                responses[response.id] = Response(interactionId: .init(response.generationId ?? response.id))
            }
        case .assistantTranscriptDelta(let delta):
            update(
                responseId: delta.responseId,
                itemId: delta.itemId,
                contentIndex: delta.contentIndex,
                change: .delta(delta.delta),
                context: &context
            )
        case .assistantTranscriptDone(let transcript):
            update(
                responseId: transcript.responseId,
                itemId: transcript.itemId,
                contentIndex: transcript.contentIndex,
                change: .final(transcript.transcript),
                context: &context
            )
        case .responseDone(let response):
            finish(response.id, context: &context)
        default:
            break
        }
    }

    /// A connection ending also ends its partial assistant messages.
    mutating func reset(context: inout LLMContext) {
        for responseId in Array(responses.keys) {
            finish(responseId, context: &context)
        }
    }

    private mutating func update(
        responseId: String,
        itemId: String,
        contentIndex: Int,
        change: Change,
        context: inout LLMContext
    ) {
        let messageId = UUID.deterministic(from: itemId)
        let existingIndex = context.firstIndex(where: { $0.id == messageId })
        if let existingIndex {
            guard context[existingIndex].role == .assistant, !context[existingIndex].complete else {
                return
            }
        }
        var response = responses[responseId] ?? Response(interactionId: .init(responseId))
        var parts = response.items[itemId] ?? [:]
        var part = parts[contentIndex] ?? Part()
        switch change {
        case .final(let content):
            // The final transcript is authoritative, including when no deltas preceded it.
            part.content = content
            part.complete = true
        case .delta(let content):
            if !part.complete {
                part.content += content
            }
        }
        parts[contentIndex] = part
        response.items[itemId] = parts
        responses[responseId] = response
        let text = parts.keys.sorted().compactMap { parts[$0]?.content }.joined()
        if let existingIndex {
            context[existingIndex].content = text
        } else {
            context.append(.init(
                id: messageId,
                role: .assistant,
                interactionId: response.interactionId,
                content: text,
                complete: false
            ))
        }
    }

    private mutating func finish(_ responseId: String, context: inout LLMContext) {
        guard let response = responses.removeValue(forKey: responseId) else {
            return
        }
        for itemId in response.items.keys {
            context.markAssistantOutputCompleted(id: UUID.deterministic(from: itemId))
        }
    }
}
