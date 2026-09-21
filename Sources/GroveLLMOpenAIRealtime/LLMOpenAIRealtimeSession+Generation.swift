//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient


@available(iOS 18, macOS 15, watchOS 11, *)
private struct RealtimeGeneration {
    enum Update {
        case text(String)
        case finished
        case none
    }

    struct Part: Hashable {
        // periphery:ignore - read by synthesized Hashable to distinguish transcript parts
        let responseId: String
        // periphery:ignore - read by synthesized Hashable to distinguish transcript parts
        let itemId: String
        // periphery:ignore - read by synthesized Hashable to distinguish transcript parts
        let contentIndex: Int
    }

    let id: String
    var eventIds: Set<String>
    var responseIds: Set<String> = []
    var text: [Part: String] = [:]

    init(id: String, conversationEventId: String) {
        self.id = id
        eventIds = [id, conversationEventId]
    }

    // swiftlint:disable:next cyclomatic_complexity
    mutating func consume(_ event: LLMRealtimeAudioEvent) throws -> Update {
        switch event {
        case .responseRequested(let request) where request.generationId == id:
            eventIds.insert(request.eventId)
        case let .generationEventSent(generationId, eventId) where generationId == id:
            eventIds.insert(eventId)
        case .responseCreated(let response) where owns(response):
            responseIds.insert(response.id)
        case .assistantTranscriptDelta(let delta) where responseIds.contains(delta.responseId):
            let part = Part(responseId: delta.responseId, itemId: delta.itemId, contentIndex: delta.contentIndex)
            text[part, default: ""].append(delta.delta)
            return .text(delta.delta)
        case .assistantTranscriptDone(let transcript) where responseIds.contains(transcript.responseId):
            return finishTranscript(transcript)
        case .responseDone(let response) where responseIds.contains(response.id) || owns(response):
            switch response.status {
            case .completed:
                // A completed tool call is one response, but its answer is still part of this generation.
                return response.functionCalls.isEmpty ? .finished : .none
            case .cancelled:
                throw CancellationError()
            case .failed, .incomplete, .inProgress:
                throw LLMOpenAIRealtimeConnection.RealtimeError.responseFailed(
                    message: response.failureMessage ?? "The response ended with status \(response.status.rawValue)."
                )
            }
        case .serverError(let error) where error.event_id.map(eventIds.contains) == true:
            throw LLMOpenAIRealtimeConnection.RealtimeError.openAIError(error: error)
        case let .generationFailed(generationId, error) where generationId == id:
            throw error
        default:
            break
        }
        return .none
    }

    private func owns(_ response: LLMRealtimeAudioEvent.Response) -> Bool {
        response.generationId == id && response.requestId.map(eventIds.contains) == true
    }

    private mutating func finishTranscript(_ transcript: LLMRealtimeAudioEvent.AssistantTranscriptDone) -> Update {
        let part = Part(responseId: transcript.responseId, itemId: transcript.itemId, contentIndex: transcript.contentIndex)
        let previous = text[part, default: ""]
        // Some responses provide the complete text without deltas. Do not duplicate text already streamed.
        guard transcript.transcript.hasPrefix(previous) else {
            return .none
        }
        text[part] = transcript.transcript
        let remainder = String(transcript.transcript.dropFirst(previous.count))
        return remainder.isEmpty ? .none : .text(remainder)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession {
    /// Follows only the responses belonging to this generation, including its tool continuations.
    static func textResponse(
        from events: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>,
        requestId: String,
        conversationEventId: String
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var generation = RealtimeGeneration(id: requestId, conversationEventId: conversationEventId)
                do {
                    for try await event in events {
                        switch try generation.consume(event) {
                        case .text(let text):
                            continuation.yield(text)
                        case .finished:
                            continuation.finish()
                            return
                        case .none:
                            break
                        }
                    }
                    try Task.checkCancellation()
                    throw LLMOpenAIRealtimeConnection.RealtimeError.responseFailed(message: "The connection ended before the response completed.")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    @MainActor
    func requestGeneration(requestId: String, conversationEventId: String, connectionId: UUID) async throws {
        typealias ConversationItemCreate = Components.Schemas.RealtimeClientEventConversationItemCreate
        let lastContext = context.last { $0.role == .user && $0.complete }
        try await apiConnection.sendMessage(
            ConversationItemCreate(
                event_id: conversationEventId,
                _type: .conversation_period_item_period_create,
                item: .init(value2: .init(
                    _type: .message, role: .user, content: [.init(_type: .input_text, text: lastContext?.content ?? "")]
                ))
            ),
            eventId: conversationEventId,
            generationId: requestId,
            connectionId: connectionId
        )
        try await apiConnection.requestResponse(eventId: requestId, generationId: requestId, connectionId: connectionId)
    }
}
