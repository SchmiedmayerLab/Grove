//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeConnection {
    enum RealtimeError: LLMError {
        case malformedUrlError
        case socketNotFoundError
        case openAIError(error: Components.Schemas.RealtimeServerEventError.errorPayload)
        case eventSessionUpdateSerialisationError
        case responseFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .responseFailed(let message): message
            case .openAIError(let error): error.message
            default: nil
            }
        }
    }

    /// Decodes response ownership before exposing events to generation and context subscribers.
    /// Unrelated event kinds are left for the session event loop.
    func processResponseEvent(data: Data, connectionId expectedConnectionId: UUID? = nil) async throws -> Bool {
        struct EventType: Decodable {
            let type: String
        }

        struct ResponseEvent: Decodable {
            let response: LLMRealtimeAudioEvent.Response
        }

        try checkConnection(expectedConnectionId)
        let events = eventStream
        let decoder = JSONDecoder()
        switch try decoder.decode(EventType.self, from: data).type {
        case "response.created":
            let response = try decoder.decode(ResponseEvent.self, from: data).response
            responseCreated(id: response.id, requestId: response.requestId, generationId: response.generationId)
            await events.broadcast(.responseCreated(response))
        case "response.done":
            let response = try preservingResponseIdentity(decoder.decode(ResponseEvent.self, from: data).response)
            // Completion also settles the matching request reservation.
            if let requestId = response.requestId {
                pendingResponseRequests.removeAll { $0 == requestId }
            }
            responseFinished(id: response.id)
            await events.broadcast(.responseDone(response))
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.output_text.delta", "response.text.delta":
            let transcript = try decoder.decode(LLMRealtimeAudioEvent.AssistantTranscriptDelta.self, from: data)
            await events.broadcast(.assistantTranscriptDelta(transcript))
        case "response.output_audio_transcript.done", "response.audio_transcript.done", "response.output_text.done", "response.text.done":
            let transcript = try decoder.decode(LLMRealtimeAudioEvent.AssistantTranscriptDone.self, from: data)
            await events.broadcast(.assistantTranscriptDone(transcript))
        default:
            return false
        }
        return true
    }

    private func preservingResponseIdentity(_ response: LLMRealtimeAudioEvent.Response) -> LLMRealtimeAudioEvent.Response {
        guard let request = responseRequests[response.id] else {
            return response
        }
        return .init(
            id: response.id,
            requestId: request.eventId,
            generationId: request.generationId,
            status: response.status,
            functionCalls: response.functionCalls,
            failureMessage: response.failureMessage
        )
    }
}
