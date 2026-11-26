//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
@testable import GroveLLM
@testable import GroveLLMOpenAI
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing


struct OpenAIGenerationTests {
    private final class Fixture: Sendable {
        let events = Mutex<[LLMGenerationEvent]>([])
        let error = Mutex<(any Error)?>(nil)

        func invocation(limit: Int = .max) -> OpenAIGeneration {
            OpenAIGeneration(send: { event in
                self.events.withLock {
                    guard $0.count < limit else {
                        return false
                    }
                    $0.append(event)
                    return true
                }
            }, terminate: { error in self.error.withLock { $0 = error } })
        }
    }

    private final class TransientTransport: ClientTransport {
        let calls = Mutex(0)

        func send(
            _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
        ) async throws -> (HTTPResponse, HTTPBody?) {
            calls.withLock {
                $0 += 1
                return (HTTPResponse(status: $0 == 1 ? .serviceUnavailable : .ok), nil)
            }
        }
    }

    @Test func retryAndToolRound() async throws {
        let fixture = Fixture()
        let invocation = fixture.invocation()
        let retry = RetryMiddleware(policy: .attempts(2), delay: .none)
        let transport = RetryMiddleware.Transport(TransientTransport())
        let url = try #require(URL(string: "https://example.invalid"))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.invalid", path: "/")
        invocation.beginRequest()
        _ = try await invocation.observingAttempts {
            try await retry.intercept(request, body: nil, baseURL: url, operationID: "test") { request, body, url in
                try await transport.send(request, body: body, baseURL: url, operationID: "test")
            }
        }
        invocation.observe(id: "one", model: nil, input: 1, output: 2, reason: .toolCalls)
        invocation.endRequest(.completed)
        invocation.beginRequest()
        invocation.dispatch()
        invocation.observe(responseEvent: Data(#"{"response":{"id":"two","model":"model","usage":{"input_tokens":3,"output_tokens":5}}}"#.utf8))
        invocation.endRequest(.completed)
        invocation.finish()
        let events = fixture.events.withLock { $0 }
        let requests = events.compactMap { if case .requestFinished(let result) = $0 { result } else { nil as LLMRequestResult? } }
        #expect(requests.map(\.request) == [1, 1, 2])
        #expect(requests.map(\.attempt) == [1, 2, 1])
        #expect(requests.map(\.status) == [.failed, .completed, .completed])
        #expect(requests.map(\.providerID) == [nil, "one", "two"])
        #expect(requests.map(\.usage) == [.init(), .init(inputTokens: 1, outputTokens: 2), .init(inputTokens: 3, outputTokens: 5)])
        #expect(events.count == 4)
        #expect(events.last == .finished(.init(status: .completed, attempts: 3, usage: .init())))
    }

    @Test func disabledRetryMakesOneDispatch() async throws {
        let underlying = TransientTransport()
        let transport = RetryMiddleware.Transport(underlying)
        let retry = RetryMiddleware(policy: .never)
        let url = try #require(URL(string: "https://example.invalid"))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.invalid", path: "/")
        let (response, _) = try await retry.intercept(request, body: nil, baseURL: url, operationID: "test") { request, body, url in
            try await transport.send(request, body: body, baseURL: url, operationID: "test")
        }
        #expect(response.status == .serviceUnavailable)
        #expect(underlying.calls.withLock { $0 } == 1)
    }

    @Test func incompleteAndPartialUsage() {
        let fixture = Fixture()
        let invocation = fixture.invocation()
        for request in 1...2 {
            invocation.beginRequest()
            invocation.dispatch()
            invocation.observe(id: nil, model: nil, input: request, output: request == 1 ? 0 : nil)
            invocation.endRequest(request == 1 ? .completed : .incomplete)
        }
        invocation.finish()
        #expect(fixture.events.withLock { $0.last } == .finished(.init(status: .incomplete, attempts: 2, usage: .init(inputTokens: 3))))
        #expect(fixture.error.withLock { $0 == nil })
    }

    @Test func overflowAndCancellationStayLocal() {
        let stalled = Fixture()
        let first = stalled.invocation(limit: 1)
        let secondFixture = Fixture()
        let second = secondFixture.invocation()
        first.beginRequest()
        first.dispatch()
        first.text("a")
        first.text("b")
        #expect(first.isCancelled)
        #expect(stalled.error.withLock { $0 is LLMGenerationStreamError })
        #expect(!second.isCancelled)
        second.finish(throwing: CancellationError())
        #expect(secondFixture.events.withLock { $0.last } == .finished(.init(status: .cancelled, attempts: 0, usage: .init())))
        #expect(secondFixture.error.withLock { $0 is CancellationError })
    }

    @Test func boundedStreamRetainsAcceptedTextAndThrows() async throws {
        let (invocation, stream) = OpenAIGeneration.stream(capacity: 2) { $0 }
        invocation.beginRequest()
        invocation.dispatch()
        invocation.text("first")
        invocation.text("second")
        invocation.text("overflow")
        #expect(invocation.isCancelled)
        var accepted: [LLMGenerationEvent] = []
        do {
            for try await event in stream { accepted.append(event) }
            Issue.record("Expected buffer overflow")
        } catch LLMGenerationStreamError.bufferOverflow {
            #expect(accepted == [.textDelta("first"), .textDelta("second")])
        }
    }

    @Test func failedRequestPrecedesThrownError() async throws {
        let (invocation, stream) = OpenAIGeneration.stream { $0 }
        invocation.beginRequest()
        invocation.dispatch()
        invocation.text("partial")
        invocation.observe(id: nil, model: nil, input: nil, output: nil, reason: .interrupted)
        invocation.finish(throwing: LLMOpenAIError.generationError)
        var events: [LLMGenerationEvent] = []
        do {
            for try await event in stream { events.append(event) }
            Issue.record("Expected generation failure")
        } catch LLMOpenAIError.generationError {
            var request = LLMRequestResult(request: 1, attempt: 1, status: .failed)
            request.reason = .interrupted
            #expect(events == [
                .textDelta("partial"), .requestFinished(request),
                .finished(.init(status: .failed, attempts: 1, usage: .init()))
            ])
        }
    }

    @Test func cancellingIteratorStopsOnlyItsInvocation() async throws {
        let (invocation, stream) = OpenAIGeneration.stream { $0 }
        let other = Fixture().invocation()
        let consumer = Task {
            for try await _ in stream {}
        }
        consumer.cancel()
        _ = await consumer.result
        #expect(invocation.isCancelled)
        #expect(!other.isCancelled)
    }

    @Test func discardedQueuedInvocationTerminates() async throws {
        let queue = LLMInferenceQueue<String>(maxConcurrentTasks: 1)
        let (invocation, stream) = OpenAIGeneration.stream { $0 }
        try queue.enqueue(discard: { invocation.finish(throwing: CancellationError()) }) {
            Issue.record("A discarded job started")
        }
        queue.shutdown()
        var events: [LLMGenerationEvent] = []
        do {
            for try await event in stream { events.append(event) }
            Issue.record("Expected queue cancellation")
        } catch is CancellationError {
            #expect(events == [.finished(.init(status: .cancelled, attempts: 0, usage: .init()))])
        }
    }

    @Test(arguments: ["length", "stop", "eof"])
    func chatWireUsageAfterChoice(reason: String) throws {
        let fixture = Fixture()
        let invocation = fixture.invocation()
        invocation.beginRequest()
        invocation.dispatch()
        var parser = OpenAIChatStream()
        let delta = ["role": "assistant", "content": "partial"]
        let choice: [[String: Any]] = [["index": 0, "delta": delta, "finish_reason": reason == "eof" ? "stop" : reason]]
        func data(choices: [[String: Any]], usage: [String: Int] = [:]) throws -> String {
            var chunk: [String: Any] = [
                "id": "chat", "object": "chat.completion.chunk", "created": 1, "model": "fixture", "choices": choices
            ]
            if !usage.isEmpty { chunk["usage"] = usage }
            return try String(decoding: JSONSerialization.data(withJSONObject: chunk), as: UTF8.self)
        }
        let text = try parser.consume(data(choices: choice), for: invocation)?.choices.first?.delta.content
        #expect(text == "partial")
        if reason == "eof" {
            #expect(throws: LLMOpenAIError.generationError) { try parser.finish(invocation) }
            invocation.finish(throwing: LLMOpenAIError.generationError)
        } else {
            _ = try parser.consume(data(choices: [], usage: ["prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5]), for: invocation)
            _ = try parser.consume("[DONE]", for: invocation)
            try parser.finish(invocation)
            invocation.finish()
        }
        let events = fixture.events.withLock { $0 }
        guard case let .requestFinished(request) = events.first else {
            Issue.record("Missing request outcome")
            return
        }
        #expect(request.reason == (reason == "eof" ? .interrupted : reason == "length" ? .outputLimit : .stop))
        #expect(request.usage == (reason == "eof" ? .init() : .init(inputTokens: 3, outputTokens: 2)))
        #expect(request.status == (reason == "eof" ? .failed : reason == "length" ? .incomplete : .completed))
        #expect(events.last == .finished(.init(status: request.status, attempts: 1, usage: request.usage)))
    }

    @Test func responsesTerminalAndReportedUsage() throws {
        let fixture = Fixture()
        let invocation = fixture.invocation()
        invocation.beginRequest()
        invocation.dispatch()
        let event = #"{"type":"response.incomplete","response":{"id":"response","model":"fixture","status":"incomplete","#
            + #""usage":{"input_tokens":false,"output_tokens":0},"incomplete_details":{"reason":"max_output_tokens"}}}"#
        invocation.observe(responseEvent: Data(event.utf8))
        let status = try OpenAIGeneration.responseStatus("incomplete", expected: "incomplete")
        invocation.endResponse(status, hasTools: true)
        invocation.finish()
        let events = fixture.events.withLock { $0 }
        guard case .requestFinished(let request) = events.first else {
            Issue.record("Missing request outcome")
            return
        }
        #expect(request.providerID == "response")
        #expect(request.reason == .outputLimit)
        #expect(events.last == .finished(.init(status: .incomplete, attempts: 1, usage: .init(outputTokens: 0))))
        #expect(throws: LLMOpenAIError.generationError) { try OpenAIGeneration.responseStatus("failed") }
        #expect(throws: LLMOpenAIError.generationError) { try OpenAIGeneration.responseStatus("in_progress", expected: "completed") }
        #expect(throws: CancellationError.self) { try OpenAIGeneration.responseStatus("cancelled") }
    }
}
