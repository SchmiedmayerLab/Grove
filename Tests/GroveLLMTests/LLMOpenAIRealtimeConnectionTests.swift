//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLMOpenAIRealtime
import Testing


@Suite("Realtime Connection")
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
        await connection.responseCreated(id: "resp-2")
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

    @Test("A request that cannot be sent gives its turn back")
    func requestWithoutSocket() async {
        let connection = LLMOpenAIRealtimeConnection()
        await #expect(throws: LLMOpenAIRealtimeConnection.RealtimeError.self) {
            try await connection.requestResponse()
        }
        #expect(await connection.pendingResponseRequests.isEmpty)
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
    func waitForWaiters(_ count: Int) async {
        while idleWaiters.count < count {
            await Task.yield()
        }
    }
}
