//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
@testable import GroveLLMOpenAIRealtime
import Testing


@Suite("Realtime Generation")
struct LLMOpenAIRealtimeGenerationTests {
    @Test("A buffered refusal fails its generation", arguments: ["response-request", "conversation-request"])
    func refusedGeneration(eventId: String) async throws {
        let broadcaster = EventBroadcaster<LLMRealtimeAudioEvent>()
        let events = await broadcaster.observe()
        // The server can reply before the caller begins iterating its pre-registered subscription.
        await broadcaster.broadcast(.serverError(try refusal(eventId: eventId)))
        await broadcaster.finish()
        let response = response(from: events)
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            for try await _ in response {}
        }
    }

    @Test("A refusal leaves other subscribers reusable")
    func otherSubscribersSurviveRefusal() async throws {
        let broadcaster = EventBroadcaster<LLMRealtimeAudioEvent>()
        let rejected = response(from: await broadcaster.observe())
        let nextEvents = await broadcaster.observe()
        await broadcaster.broadcast(.serverError(try refusal(eventId: "response-request")))
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            for try await _ in rejected {}
        }
        await broadcaster.broadcast(.responseRequested("next-request"))
        await broadcaster.broadcast(.assistantTranscriptDelta("Hello"))
        await broadcaster.broadcast(.assistantTranscriptDone("Hello"))
        await broadcaster.finish()
        let next = LLMOpenAIRealtimeSession.textResponse(
            from: nextEvents,
            requestId: "next-request",
            conversationEventId: "next-conversation"
        )
        var text = ""
        for try await delta in next {
            text += delta
        }
        #expect(text == "Hello")
    }

    @Test("A generation ignores transcripts buffered while waiting for its turn")
    func ignoresPreviousResponse() async throws {
        let broadcaster = EventBroadcaster<LLMRealtimeAudioEvent>()
        let events = await broadcaster.observe()
        await broadcaster.broadcast(.assistantTranscriptDelta("Previous response"))
        await broadcaster.broadcast(.assistantTranscriptDone("Previous response"))
        await broadcaster.broadcast(.responseRequested("response-request"))
        await broadcaster.broadcast(.assistantTranscriptDelta("Current response"))
        await broadcaster.broadcast(.assistantTranscriptDone("Current response"))
        await broadcaster.finish()
        var text = ""
        for try await delta in response(from: events) {
            text += delta
        }
        #expect(text == "Current response")
    }

    @Test("Transcription uses the server's GA or beta configuration")
    func effectiveTranscriptionConfiguration() {
        #expect(LLMOpenAIRealtimeConnection.transcriptionEnabled(in: [
            "session": ["audio": ["input": ["transcription": ["model": "gpt-4o-transcribe"]]]]
        ]))
        #expect(LLMOpenAIRealtimeConnection.transcriptionEnabled(in: [
            "session": ["input_audio_transcription": ["model": "whisper-1"]]
        ]))
        #expect(!LLMOpenAIRealtimeConnection.transcriptionEnabled(in: [
            "session": ["audio": ["input": ["transcription": NSNull()]]]
        ]))
        #expect(!LLMOpenAIRealtimeConnection.transcriptionEnabled(in: [
            "session": ["input_audio_transcription": NSNull()]
        ]))
        #expect(!LLMOpenAIRealtimeConnection.transcriptionEnabled(in: ["session": [:]]))
    }

    private func response(
        from events: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>
    ) -> AsyncThrowingStream<String, any Error> {
        LLMOpenAIRealtimeSession.textResponse(from: events, requestId: "response-request", conversationEventId: "conversation-request")
    }

    private func refusal(eventId: String) throws -> Components.Schemas.RealtimeServerEventError.errorPayload {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "invalid_request_error",
            "code": "invalid_value",
            "message": "The requested response was rejected.",
            "event_id": eventId
        ])
        return try JSONDecoder().decode(Components.Schemas.RealtimeServerEventError.errorPayload.self, from: data)
    }
}
