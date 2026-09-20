//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLMOpenAI
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
        await broadcaster.broadcast(request("next-request"))
        await broadcaster.broadcast(.responseCreated(serverResponse("next", requestId: "next-request")))
        await broadcaster.broadcast(delta("Hello", responseId: "next"))
        await broadcaster.broadcast(transcript("Hello", responseId: "next"))
        await broadcaster.broadcast(.responseDone(serverResponse("next", requestId: "next-request", status: .completed)))
        await broadcaster.finish()
        let text = try await collect(from: nextEvents, requestId: "next-request")
        #expect(text == "Hello")
    }

    @Test("A generation ignores transcripts buffered while waiting for its turn")
    func ignoresPreviousResponse() async throws {
        let text = try await collect([
            .responseCreated(serverResponse("previous", requestId: "previous-request")),
            delta("Previous response", responseId: "previous"),
            transcript("Previous response", responseId: "previous"),
            .responseDone(serverResponse("previous", requestId: "previous-request", status: .completed)),
            request(),
            .responseCreated(serverResponse()),
            delta("Current response"),
            transcript("Current response"),
            .responseDone(serverResponse(status: .completed))
        ])
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
}


extension LLMOpenAIRealtimeGenerationTests {
    @Test("Concurrent generations keep interleaved voice and assistant responses separate")
    func concurrentGenerations() async throws {
        let broadcaster = EventBroadcaster<LLMRealtimeAudioEvent>()
        let firstEvents = await broadcaster.observe()
        let secondEvents = await broadcaster.observe()
        let events: [LLMRealtimeAudioEvent] = [
            request("first-request"),
            request("second-request"),
            .responseCreated(serverResponse("voice", requestId: nil)),
            delta("Automatic voice", responseId: "voice"),
            .responseCreated(serverResponse("second", requestId: "second-request")),
            .responseCreated(serverResponse("first", requestId: "first-request")),
            delta("First", responseId: "first"),
            delta("Second", responseId: "second"),
            transcript("Automatic voice", responseId: "voice"),
            .responseDone(serverResponse("voice", requestId: nil, status: .completed)),
            transcript("Second response", responseId: "second"),
            .responseDone(serverResponse("second", requestId: "second-request", status: .completed)),
            delta(" response", responseId: "first"),
            transcript("First response", responseId: "first"),
            .responseDone(serverResponse("first", requestId: "first-request", status: .completed))
        ]
        for event in events {
            await broadcaster.broadcast(event)
        }
        await broadcaster.finish()
        async let first = collect(from: firstEvents, requestId: "first-request")
        async let second = collect(from: secondEvents, requestId: "second-request")
        let (firstText, secondText) = try await (first, second)
        #expect(firstText == "First response")
        #expect(secondText == "Second response")
    }

    @Test("A tool-only response waits through an interjection for its own continuation")
    func toolContinuation() async throws {
        let text = try await collect([
            request(),
            .responseCreated(serverResponse()),
            .responseDone(serverResponse(status: .completed, functionCalls: [toolCall])),
            request("interjection-request", generationId: nil),
            .responseCreated(serverResponse("interjection", requestId: "interjection-request", generationId: nil)),
            delta("Unrelated interjection", responseId: "interjection"),
            .responseDone(serverResponse("interjection", requestId: "interjection-request", generationId: nil, status: .completed)),
            .generationEventSent(generationId: "response-request", eventId: "tool-output"),
            request("followup-request", generationId: "response-request"),
            .responseCreated(serverResponse("followup", requestId: "followup-request", generationId: "response-request")),
            delta("Tool result", responseId: "followup"),
            transcript("Tool result", responseId: "followup"),
            .responseDone(serverResponse("followup", requestId: "followup-request", generationId: "response-request", status: .completed))
        ])
        #expect(text == "Tool result")
    }

    @Test("Finishing a transcript part does not finish the generation")
    func multipleTranscriptParts() async throws {
        let text = try await collect([
            request(),
            .responseCreated(serverResponse()),
            delta("First"),
            transcript("First part"),
            // A repeated final transcript must not repeat already emitted text.
            transcript("First part"),
            delta("Second", contentIndex: 1),
            transcript("Second part", contentIndex: 1),
            transcript("Third part", itemId: "another-item"),
            .responseDone(serverResponse(status: .completed))
        ])
        #expect(text == "First partSecond partThird part")
    }

    @Test("An empty successful response completes without transcript events")
    func emptyResponse() async throws {
        let text = try await collect([
            request(),
            .responseCreated(serverResponse()),
            .responseDone(serverResponse(status: .completed))
        ])
        #expect(text.isEmpty)
    }

    @Test("Response metadata must identify both the request and its generation")
    func mismatchedMetadata() async throws {
        let text = try await collect([
            request(),
            .responseCreated(serverResponse("wrong-generation", generationId: "another-generation")),
            delta("Wrong generation", responseId: "wrong-generation"),
            .responseDone(serverResponse("wrong-generation", generationId: "another-generation", status: .completed)),
            .responseCreated(serverResponse("wrong-request", requestId: "another-request", generationId: "response-request")),
            delta("Wrong request", responseId: "wrong-request"),
            .responseDone(serverResponse("wrong-request", requestId: "another-request", generationId: "response-request", status: .completed)),
            .responseCreated(serverResponse()),
            delta("Owned response"),
            .responseDone(serverResponse(status: .completed))
        ])
        #expect(text == "Owned response")
    }

    @Test("An unrelated terminal failure cannot terminate a generation")
    func unrelatedFailures() async throws {
        let text = try await collect([
            request(),
            .responseCreated(serverResponse()),
            .serverError(try refusal(eventId: "unrelated-request")),
            .generationFailed(generationId: "unrelated-generation", error: TestFailure.toolExecution),
            .responseDone(serverResponse("unrelated", requestId: nil, status: .failed)),
            delta("Still active"),
            .responseDone(serverResponse(status: .completed))
        ])
        #expect(text == "Still active")
    }
}


extension LLMOpenAIRealtimeGenerationTests {
    @Test("Failed or incomplete responses fail even without transcript events", arguments: ["failed", "incomplete"])
    func unsuccessfulResponse(status: String) async {
        let terminalStatus: LLMRealtimeAudioEvent.Response.Status = status == "failed" ? .failed : .incomplete
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await collect([
                request(),
                .responseCreated(serverResponse()),
                .responseDone(serverResponse(status: terminalStatus))
            ])
        }
    }

    @Test("A cancelled response cancels its generation without requiring transcript events")
    func cancelledResponse() async {
        await #expect(throws: CancellationError.self) {
            try await collect([
                request(),
                .responseCreated(serverResponse()),
                .responseDone(serverResponse(status: .cancelled))
            ])
        }
    }

    @Test("Refused tool output and follow-up requests fail the original generation", arguments: ["tool-output", "followup-request"])
    func refusedContinuation(eventId: String) async throws {
        let events: [LLMRealtimeAudioEvent] = [
            request(),
            .responseCreated(serverResponse()),
            .responseDone(serverResponse(status: .completed, functionCalls: [toolCall])),
            .generationEventSent(generationId: "response-request", eventId: "tool-output"),
            request("followup-request", generationId: "response-request"),
            .serverError(try refusal(eventId: eventId))
        ]
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await collect(events)
        }
    }

    @Test("A local tool execution failure fails the original generation")
    func failedToolExecution() async {
        await #expect(throws: TestFailure.self) {
            try await collect([
                request(),
                .responseCreated(serverResponse()),
                .responseDone(serverResponse(status: .completed, functionCalls: [toolCall])),
                .generationFailed(generationId: "response-request", error: TestFailure.toolExecution)
            ])
        }
    }

    @Test("A disconnected stream cannot report a partial or pending generation as successful", arguments: [false, true])
    func prematureStreamEnd(afterTranscript: Bool) async {
        var events: [LLMRealtimeAudioEvent] = [request(), .responseCreated(serverResponse())]
        if afterTranscript {
            events.append(transcript("Partial answer"))
        }
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await collect(events)
        }
    }
}


extension LLMOpenAIRealtimeGenerationTests {
    private enum TestFailure: Error {
        case toolExecution
    }

    private var toolCall: LLMOpenAIStreamResult.FunctionCall {
        .init(name: "lookup", id: "call-1", arguments: "{}")
    }

    private func request(_ eventId: String = "response-request") -> LLMRealtimeAudioEvent {
        request(eventId, generationId: eventId)
    }

    private func request(_ eventId: String, generationId: String?) -> LLMRealtimeAudioEvent {
        .responseRequested(.init(eventId: eventId, generationId: generationId))
    }

    private func serverResponse(
        _ id: String = "response",
        requestId: String? = "response-request",
        status: LLMRealtimeAudioEvent.Response.Status = .inProgress,
        functionCalls: [LLMOpenAIStreamResult.FunctionCall] = []
    ) -> LLMRealtimeAudioEvent.Response {
        serverResponse(id, requestId: requestId, generationId: requestId, status: status, functionCalls: functionCalls)
    }

    private func serverResponse(
        _ id: String = "response",
        requestId: String? = "response-request",
        generationId: String?,
        status: LLMRealtimeAudioEvent.Response.Status = .inProgress,
        functionCalls: [LLMOpenAIStreamResult.FunctionCall] = []
    ) -> LLMRealtimeAudioEvent.Response {
        .init(
            id: id,
            requestId: requestId,
            generationId: generationId,
            status: status,
            functionCalls: functionCalls,
            failureMessage: nil
        )
    }

    private func delta(
        _ text: String,
        responseId: String = "response",
        itemId: String = "item",
        contentIndex: Int = 0
    ) -> LLMRealtimeAudioEvent {
        .assistantTranscriptDelta(.init(responseId: responseId, itemId: itemId, contentIndex: contentIndex, delta: text))
    }

    private func transcript(
        _ text: String,
        responseId: String = "response",
        itemId: String = "item",
        contentIndex: Int = 0
    ) -> LLMRealtimeAudioEvent {
        .assistantTranscriptDone(.init(responseId: responseId, itemId: itemId, contentIndex: contentIndex, transcript: text))
    }

    private func response(
        from events: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>
    ) -> AsyncThrowingStream<String, any Error> {
        LLMOpenAIRealtimeSession.textResponse(from: events, requestId: "response-request", conversationEventId: "conversation-request")
    }

    private func collect(_ events: [LLMRealtimeAudioEvent]) async throws -> String {
        let stream = AsyncThrowingStream<LLMRealtimeAudioEvent, any Error> { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
        return try await collect(from: stream, requestId: "response-request")
    }

    private func collect(from events: AsyncThrowingStream<LLMRealtimeAudioEvent, any Error>, requestId: String) async throws -> String {
        var text = ""
        let response = LLMOpenAIRealtimeSession.textResponse(from: events, requestId: requestId, conversationEventId: "conversation-request")
        for try await delta in response {
            text += delta
        }
        return text
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
