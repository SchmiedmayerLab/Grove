//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLMOpenAI
@testable import GroveLLMOpenAIRealtime
import Testing


@Suite("Realtime Connection", .timeLimit(.minutes(1)))
struct LLMOpenAIRealtimeConnectionTests {
    @Test("The socket sits next to the REST endpoint")
    func socketNextToEndpoint() throws {
        let url = try LLMOpenAIRealtimeConnection.realtimeSocketUrl(
            from: URL(string: "https://api.openai.com/v1")!,
            model: "gpt-realtime"
        )
        #expect(url.absoluteString == "wss://api.openai.com/v1/realtime?model=gpt-realtime")
    }

    @Test("A gateway path and a trailing slash are kept")
    func gatewayPath() throws {
        let url = try LLMOpenAIRealtimeConnection.realtimeSocketUrl(
            from: URL(string: "https://aiapi-prod.stanford.edu/v1/")!,
            model: "gpt-realtime-mini"
        )
        #expect(url.absoluteString == "wss://aiapi-prod.stanford.edu/v1/realtime?model=gpt-realtime-mini")
    }

    @Test("Plain HTTP becomes a plain socket")
    func plainSocket() throws {
        let url = try LLMOpenAIRealtimeConnection.realtimeSocketUrl(
            from: URL(string: "http://localhost:4000/v1")!,
            model: "gpt-realtime"
        )
        #expect(url.scheme == "ws")
        #expect(url.port == 4000)
    }

    @Test("Response turns go out one at a time")
    func responseTurnsAreSerialized() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "resp-1")
        async let first: Void = connection.waitUntilResponseIdle(reserving: "event-1", timeout: .seconds(5))
        await connection.waitForWaiters(1)
        async let second: Void = connection.waitUntilResponseIdle(reserving: "event-2", timeout: .seconds(5))
        await connection.waitForWaiters(2)

        await connection.responseFinished(id: "resp-1")
        await first
        #expect(await connection.pendingResponseRequests == ["event-1"])
        #expect(await connection.idleWaiters.map(\.eventId) == ["event-2"])

        // Only once the first request has been created and its response is over does the second get its turn.
        await connection.responseCreated(id: "resp-2", requestId: "event-1")
        await connection.responseFinished(id: "resp-2")
        await second
        #expect(await connection.pendingResponseRequests == ["event-2"])
    }

    @Test("A refused request hands the turn to the next waiter")
    func refusalReleasesNextWaiter() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "resp-1")
        async let first: Void = connection.waitUntilResponseIdle(reserving: "event-1", timeout: .seconds(5))
        await connection.waitForWaiters(1)
        async let second: Void = connection.waitUntilResponseIdle(reserving: "event-2", timeout: .seconds(5))
        await connection.waitForWaiters(2)
        await connection.responseFinished(id: "resp-1")
        await first

        await connection.withdraw("event-1")
        await second
        #expect(await connection.pendingResponseRequests == ["event-2"])
    }

    @Test("A wait that runs out takes the turn anyway")
    func waitTimesOut() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "resp-1")
        await connection.waitUntilResponseIdle(reserving: "event-1", timeout: .milliseconds(50))
        #expect(await connection.pendingResponseRequests == ["event-1"])
        #expect(await connection.idleWaiters.isEmpty)
    }

    @Test("A cancelled interjection gives its turn back")
    func cancelledInterjection() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "resp-1")
        let interjection = Task {
            try await connection.requestInterjection("Hold on.")
        }
        await connection.waitForWaiters(1)
        interjection.cancel()
        let result = await interjection.result
        #expect(throws: CancellationError.self) {
            try result.get()
        }
        #expect(await connection.pendingResponseRequests.isEmpty)
    }

    @Test("An already cancelled response wait never registers a continuation or reservation")
    func alreadyCancelledResponseWait() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "active-response")
        // Bound a regression's hang: a stuck continuation is released, and the retained-response assertion fails.
        let fallback = Task {
            try await Task.sleep(for: .seconds(1))
            await connection.resetResponseTracking()
        }
        defer { fallback.cancel() }
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await connection.waitUntilResponseIdle(reserving: "cancelled-request", timeout: .seconds(30))
        }
        await waiter.value
        #expect(await connection.activeResponses == ["active-response"])
        #expect(await connection.idleWaiters.isEmpty)
        #expect(await connection.pendingResponseRequests.isEmpty)
    }

    @Test("A request that cannot be sent gives its turn back")
    func requestWithoutSocket() async {
        let connection = LLMOpenAIRealtimeConnection()
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await connection.requestResponse()
        }
        #expect(await connection.pendingResponseRequests.isEmpty)
    }

    @Test("A VAD response does not consume a pending local request")
    func automaticResponseKeepsLocalReservation() async throws {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.waitUntilResponseIdle(reserving: "local-request")
        let automatic = Data("""
            {"type":"response.created","response":{"id":"vad-response","status":"in_progress","metadata":null,"output":[]}}
            """.utf8)
        #expect(try await connection.processResponseEvent(data: automatic))
        #expect(await connection.pendingResponseRequests == ["local-request"])
        #expect(await connection.activeResponses == ["vad-response"])

        let local = Data("""
            {"type":"response.created","response":{"id":"local-response","status":"in_progress",
            "metadata":{"grove_request_id":"local-request","grove_generation_id":"generation"},"output":[]}}
            """.utf8)
        #expect(try await connection.processResponseEvent(data: local))
        #expect(await connection.pendingResponseRequests.isEmpty)
        #expect(await connection.activeResponses == ["vad-response", "local-response"])
    }

    @Test("Responses settle the named reservation rather than the first pending request")
    func responseReservationsMatchMetadata() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.seedPendingResponseRequests(["first-request", "second-request"])
        await connection.responseCreated(id: "second-response", requestId: "second-request")
        #expect(await connection.pendingResponseRequests == ["first-request"])
        await connection.responseCreated(id: "first-response", requestId: "first-request")
        #expect(await connection.pendingResponseRequests.isEmpty)
    }

    @Test("A completed response preserves all tool calls and their generation")
    func completedResponseCarriesTools() async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let events = await connection.events()
        await connection.waitUntilResponseIdle(reserving: "request")
        let data = Data(#"""
            {"type":"response.done","response":{"id":"response","status":"completed",
            "metadata":{"grove_request_id":"request","grove_generation_id":"generation"},"output":[
            {"type":"function_call","call_id":"call-a","name":"first","arguments":"{}"},
            {"type":"message","id":"message","content":[]},
            {"type":"function_call","call_id":"call-b","name":"second","arguments":"{\"value\":2}"}]}}
            """#.utf8)
        #expect(try await connection.processResponseEvent(data: data))
        var iterator = events.makeAsyncIterator()
        guard case .responseDone(let response)? = try await iterator.next() else {
            Issue.record("Expected a completed response event")
            return
        }
        #expect(response.id == "response")
        #expect(response.requestId == "request")
        #expect(response.generationId == "generation")
        #expect(response.status == .completed)
        #expect(response.functionCalls.map(\.id) == ["call-a", "call-b"])
        #expect(response.functionCalls.map(\.name) == ["first", "second"])
        #expect(await connection.isResponseIdle)
    }

    @Test("Response completion retains established ownership without repeating metadata")
    func completionRetainsEstablishedOwnership() async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let created = Data("""
            {"type":"response.created","response":{"id":"response","status":"in_progress",
            "metadata":{"grove_request_id":"request","grove_generation_id":"generation"}}}
            """.utf8)
        #expect(try await connection.processResponseEvent(data: created))
        #expect(await connection.responseRequests["response"]?.eventId == "request")
        let events = await connection.events()
        let done = Data("""
            {"type":"response.done","response":{"id":"response","status":"completed","metadata":null,
            "output":[{"type":"function_call","call_id":"call","name":"tool","arguments":"{}"}]}}
            """.utf8)
        #expect(try await connection.processResponseEvent(data: done))
        var iterator = events.makeAsyncIterator()
        guard case .responseDone(let response)? = try await iterator.next() else {
            Issue.record("Expected the response with its established ownership")
            return
        }
        #expect(response.requestId == "request")
        #expect(response.generationId == "generation")
        #expect(response.functionCalls.map(\.id) == ["call"])
        #expect(await connection.responseRequests.isEmpty)

        #expect(try await connection.processResponseEvent(data: created))
        await connection.resetResponseTracking()
        #expect(await connection.responseRequests.isEmpty)
    }

    @Test("Terminal responses retain their failure status even without a transcript", arguments: ["failed", "cancelled", "incomplete"])
    func terminalResponseWithoutTranscript(status: String) async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let events = await connection.events()
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "response.done",
            "response": [
                "id": "response", "status": status, "output": [],
                "status_details": ["reason": "interrupted", "error": ["message": "Response could not finish."]]
            ]
        ])
        #expect(try await connection.processResponseEvent(data: data))
        var iterator = events.makeAsyncIterator()
        guard case .responseDone(let response)? = try await iterator.next() else {
            Issue.record("Expected a terminal response event")
            return
        }
        #expect(response.status.rawValue == status)
        #expect(response.failureMessage == "Response could not finish.")
        #expect(response.functionCalls.isEmpty)
    }

    @Test("Transcript deltas preserve response and item identity", arguments: [
        "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.output_text.delta", "response.text.delta"
    ])
    func transcriptDeltaIdentity(eventType: String) async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let events = await connection.events()
        let data = try JSONSerialization.data(withJSONObject: [
            "type": eventType, "response_id": "response", "item_id": "item", "content_index": 2, "delta": "Hello"
        ])
        #expect(try await connection.processResponseEvent(data: data))
        var iterator = events.makeAsyncIterator()
        guard case .assistantTranscriptDelta(let delta)? = try await iterator.next() else {
            Issue.record("Expected a transcript delta")
            return
        }
        #expect(delta.responseId == "response")
        #expect(delta.itemId == "item")
        #expect(delta.contentIndex == 2)
        #expect(delta.delta == "Hello")
    }

    @Test("Text and audio transcript completion preserve response and item identity", arguments: [
        "response.output_audio_transcript.done", "response.audio_transcript.done", "response.output_text.done", "response.text.done"
    ])
    func transcriptDoneIdentity(eventType: String) async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let events = await connection.events()
        let textKey = eventType.hasSuffix("text.done") ? "text" : "transcript"
        let data = try JSONSerialization.data(withJSONObject: [
            "type": eventType, "response_id": "response", "item_id": "item", "content_index": 2, textKey: "Hello"
        ])
        #expect(try await connection.processResponseEvent(data: data))
        var iterator = events.makeAsyncIterator()
        guard case .assistantTranscriptDone(let transcript)? = try await iterator.next() else {
            Issue.record("Expected a completed transcript")
            return
        }
        #expect(transcript.responseId == "response")
        #expect(transcript.itemId == "item")
        #expect(transcript.contentIndex == 2)
        #expect(transcript.transcript == "Hello")
    }

    @Test("Every response request identifies itself, including interjections without a generation")
    func responseRequestMetadata() {
        let generation = LLMRealtimeAudioEvent.ResponseRequest(eventId: "request", generationId: "generation")
        #expect(generation.metadata == ["grove_request_id": "request", "grove_generation_id": "generation"])
        let interjection = LLMRealtimeAudioEvent.ResponseRequest(eventId: "interjection", generationId: nil)
        #expect(interjection.metadata == ["grove_request_id": "interjection"])
    }

    @Test("A generation owns its event before a send can fail")
    func generationRegisteredBeforeSend() async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let events = await connection.events()
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await connection.sendMessage(["type": "conversation.item.create"], eventId: "event", generationId: "generation")
        }
        var iterator = events.makeAsyncIterator()
        guard case .generationEventSent(let generationId, let eventId)? = try await iterator.next() else {
            Issue.record("Expected generation ownership before the send error")
            return
        }
        #expect(generationId == "generation")
        #expect(eventId == "event")
    }

    @Test("Work from a previous connection cannot send onto a new connection")
    func staleConnectionCannotSend() async {
        let connection = LLMOpenAIRealtimeConnection()
        let previousId = await connection.connectionId
        await connection.resetResponseTracking()
        #expect(await connection.connectionId != previousId)
        await #expect(throws: CancellationError.self) {
            try await connection.sendMessage(
                ["type": "conversation.item.create"],
                eventId: "event",
                generationId: "generation",
                connectionId: previousId
            )
        }
        await #expect(throws: CancellationError.self) {
            try await connection.requestResponse(generationId: "generation", connectionId: previousId)
        }
        #expect(await connection.pendingResponseRequests.isEmpty)
    }

    @Test("A queued response cannot cross a reconnect while waiting", arguments: [false, true])
    func queuedResponseCannotCrossReconnect(explicitConnectionId: Bool) async {
        let connection = LLMOpenAIRealtimeConnection()
        let previousId = await connection.connectionId
        await connection.responseCreated(id: "active-response")
        let request = Task {
            try await connection.requestResponse(generationId: "generation", connectionId: explicitConnectionId ? previousId : nil)
        }
        await connection.waitForWaiters(1)
        await connection.resetResponseTracking()
        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect(await connection.isResponseIdle)
    }

    @Test("A queued interjection cannot cross a reconnect")
    func queuedInterjectionCannotCrossReconnect() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "active-response")
        let request = Task {
            try await connection.requestInterjection("Hold on.")
        }
        await connection.waitForWaiters(1)
        await connection.cancel()
        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect(await connection.isResponseIdle)
    }

    @Test("An old connection's events and termination cannot affect new subscribers")
    func oldConnectionEventsStayIsolated() async throws {
        let connection = LLMOpenAIRealtimeConnection()
        let previousEvents = await connection.eventStream
        let previousStream = await connection.events()
        let previousId = await connection.connectionId
        await connection.cancel()
        let currentStream = await connection.events()
        await previousEvents.broadcast(.inputTranscriptionConfigured(false))
        await previousEvents.finish()
        await #expect(throws: CancellationError.self) {
            try await connection.processResponseEvent(
                data: Data("""
                    {"type":"response.created","response":{"id":"stale","status":"in_progress"}}
                    """.utf8),
                connectionId: previousId
            )
        }
        #expect(await connection.activeResponses.isEmpty)
        await connection.eventStream.broadcast(.inputTranscriptionConfigured(true))
        var currentIterator = currentStream.makeAsyncIterator()
        guard case .inputTranscriptionConfigured(let enabled)? = try await currentIterator.next() else {
            Issue.record("The current connection must still have a live event stream")
            return
        }
        #expect(enabled)
        var previousIterator = previousStream.makeAsyncIterator()
        #expect(try await previousIterator.next() == nil)
    }

    @Test("Resetting releases everyone waiting")
    func resetReleasesWaiters() async {
        let connection = LLMOpenAIRealtimeConnection()
        await connection.responseCreated(id: "resp-1")
        async let waiter: Void = connection.waitUntilResponseIdle(reserving: "event-1", timeout: .seconds(5))
        await connection.waitForWaiters(1)
        await connection.resetResponseTracking()
        await waiter
        #expect(await connection.isResponseIdle)
    }

    @Test("Waiting for transcripts ends when they arrive")
    func transcriptsSettle() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        async let waited: Void = tracker.waitUntilSettled(timeout: .seconds(5))
        await tracker.complete("item-1")
        await waited
    }

    @Test("Waiting for transcripts gives up after the grace period")
    func transcriptsTimeOut() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        let start = ContinuousClock.now
        await tracker.waitUntilSettled(timeout: .milliseconds(50))
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}


extension LLMOpenAIRealtimeConnection {
    func seedPendingResponseRequests(_ eventIds: [String]) {
        pendingResponseRequests = eventIds
    }

    func waitForWaiters(_ count: Int) async {
        while idleWaiters.count < count {
            await Task.yield()
        }
    }
}
