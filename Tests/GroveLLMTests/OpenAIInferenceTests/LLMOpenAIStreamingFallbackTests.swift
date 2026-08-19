//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
@testable import Grove
@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import Synchronization
import Testing


/// A tool with an unmistakable return value, so a model either called it or it didn't.
private struct FallbackTestFunction: LLMTool {
    let name = "perform_test"
    let description = "Performs a test and returns the value that proves the function was called"

    func execute() async throws -> String? {
        "The value to return to ensure the test was succesful is \"abcdefghijklmnopqrstuvwxyz\""
    }
}


/// Covers retrying a Responses API request without streaming.
///
/// A gateway can serve `/v1/responses` and still fail to stream it — Stanford's LiteLLM proxy answers `stream: true`
/// with a 500 and the same request unstreamed with a 200. These pin that such a request still produces an answer,
/// and — just as importantly — that a stream which breaks *after* output has arrived is never retried, since that
/// would repeat what the user already read.
@Suite("LLM OpenAI Streaming Fallback")
final class LLMOpenAIStreamingFallbackTests {
    private var platformTask: Task<Void, Never>?

    /// Whether the request asked the server to stream.
    private static func isStreaming(_ input: Operations.createResponse.Input) -> Bool {
        guard case let .json(body) = input.body else {
            return false
        }
        return body.value3.stream ?? false
    }

    @MainActor
    @Test("A stream rejected before any output is retried without streaming")
    func retriesAfterStreamRejection() async throws {
        let session = try makeSession()
        session.context.append(userMessage: "Hello!")

        let requests = Mutex<[Bool]>([])
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { input in
            let streamed = Self.isStreaming(input)
            requests.withLock { $0.append(streamed) }
            guard !streamed else {
                // What the gateway does: a 500 before a single event reaches the client.
                return .undocumented(statusCode: 500, .init())
            }
            var builder = ResponsesPayloadBuilder()
            builder.message("Hello world!")
            return try builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(requests.withLock { $0 } == [true, false], "the streamed attempt should come first, then the retry")
        #expect(output == "Hello world!")
        #expect(session.context.last?.role == .assistant)
        #expect(session.context.last?.content == "Hello world!")
        #expect(session.context.last?.complete == true)
    }

    @MainActor
    @Test("A streamed request answered with a plain JSON body still falls back")
    func retriesWhenTheStreamedRequestIsAnsweredWithoutStreaming() async throws {
        let session = try makeSession()
        session.context.append(userMessage: "Hello!")

        let requests = Mutex<[Bool]>([])
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { input in
            let streamed = Self.isStreaming(input)
            requests.withLock { $0.append(streamed) }
            var builder = ResponsesPayloadBuilder()
            builder.message("Hello world!")
            // Both requests answer with a JSON body; for the streamed one that is a protocol violation the
            // client surfaces as a decoding failure rather than as an API error.
            return try builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(requests.withLock { $0 } == [true, false], "the unstreamed retry has to happen here too")
        #expect(output == "Hello world!")
    }

    @MainActor
    @Test("A stream that fails after producing output is not retried")
    func doesNotRetryOncePartialOutputArrived() async throws {
        let session = try makeSession()
        session.context.append(userMessage: "Hello!")

        let requestCount = Mutex<Int>(0)
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { _ in
            requestCount.withLock { $0 += 1 }
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.outputTextDelta("Half an ")
            builder.errorEvent(message: "connection reset")
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        do {
            for try await piece in try await session.generate() {
                output.append(piece)
            }
            Issue.record("A stream failing mid-flight should surface as an error")
        } catch {
            // Expected: the failure reaches the caller rather than being papered over by a second request.
        }

        #expect(requestCount.withLock { $0 } == 1, "retrying would have repeated the text the user already saw")
        #expect(output == "Half an ")
    }

    @MainActor
    @Test("The fallback can be switched off")
    func honoursDisabledFallback() async throws {
        let session = try makeSession(streamingFallback: false)
        session.context.append(userMessage: "Hello!")

        let requestCount = Mutex<Int>(0)
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { _ in
            requestCount.withLock { $0 += 1 }
            return .undocumented(statusCode: 500, .init())
        }
        session.openAiClient = client

        do {
            for try await _ in try await session.generate() {}
            Issue.record("Without the fallback the rejected stream should surface as an error")
        } catch {
            // Expected.
        }
        #expect(requestCount.withLock { $0 } == 1)
    }

    @Test("Every announced tool call that went unanswered is reported")
    func unansweredToolCallsAreAccountedFor() {
        let calls: [LLMOpenAIStreamResult.FunctionCall] = [
            .init(name: "a", id: "call_one", arguments: "{}"),
            .init(name: "b", id: "call_two", arguments: "{}"),
            .init(name: "c", id: "call_three", arguments: "{}")
        ]

        let unanswered = LLMOpenAISession.unansweredCalls(among: calls, answered: ["call_two"])

        #expect(
            unanswered.map(\.id) == ["call_one", "call_three"],
            """
            A call the model was told about but that produced no output has to be reported. Replaying the turn \
            otherwise sends a function_call with no function_call_output, which the API rejects on every retry.
            """
        )
    }

    @Test("A call with no id is left alone, since it cannot be replayed anyway")
    func callsWithoutAnIdAreNotReported() {
        let calls: [LLMOpenAIStreamResult.FunctionCall] = [
            .init(name: "a", id: nil, arguments: "{}"),
            .init(name: "b", id: "", arguments: "{}")
        ]

        #expect(LLMOpenAISession.unansweredCalls(among: calls, answered: []).isEmpty)
    }

    @MainActor
    @Test("An unusable token is not retried, since it fails the same way unstreamed")
    func doesNotRetryUnrecoverableFailures() async throws {
        let session = try makeSession()
        session.context.append(userMessage: "Hello!")

        let requestCount = Mutex<Int>(0)
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { _ in
            requestCount.withLock { $0 += 1 }
            return .undocumented(statusCode: 401, .init())
        }
        session.openAiClient = client

        do {
            for try await _ in try await session.generate() {}
            Issue.record("An invalid token should surface as an error")
        } catch {
            // Expected.
        }
        #expect(requestCount.withLock { $0 } == 1, "a second request would fail identically")
    }

    @MainActor
    @Test("Reasoning summaries and function calls survive the fallback")
    func carriesReasoningAndFunctionCallsThroughTheFallback() async throws {
        let session = try makeSession {
            FallbackTestFunction()
        }
        session.context.append(userMessage: "Run the test function.")

        let requestCount = Mutex<Int>(0)
        let client = LLMOpenAIInferenceTests.MockChatClient()
        client.createResponseHandler = { input in
            guard !Self.isStreaming(input) else {
                return .undocumented(statusCode: 500, .init())
            }
            let callNumber = requestCount.withLock { count -> Int in
                count += 1
                return count
            }
            var builder = ResponsesPayloadBuilder()
            builder.reasoning(summary: "The user wants the test function run.")
            if callNumber == 1 {
                builder.functionCall(name: FallbackTestFunction().name, arguments: "{}")
            } else {
                builder.message("Done.")
            }
            return try builder.output(id: "resp_\(callNumber)")
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output == "Done.")
        let thinking = session.context.filter { $0.role == .assistantThinking }
        #expect(!thinking.isEmpty, "the reasoning summary should reach the context")
        #expect(!thinking.contains { !$0.complete }, "no thinking entity may be left unfinished")
        let toolResponse = session.context.first { $0.isToolCallResponse }
        #expect(toolResponse?.content.contains("abcdefghijklmnopqrstuvwxyz") == true)
    }

    @MainActor
    private func makeSession(
        streamingFallback: Bool = true,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) throws -> LLMOpenAISession {
        let platform = LLMOpenAIPlatform(
            configuration: .init(authToken: .constant("mocked-token"), streamingFallback: streamingFallback)
        )
        let runner = LLMRunner { platform }
        withDependencyResolution { runner }
        platformTask = Task { await platform.run() }

        return platform(
            with: LLMOpenAISchema(parameters: .init(modelType: .gpt5_mini), injectIntoContext: true, functions)
        )
    }

    deinit {
        platformTask?.cancel()
    }
}


extension LLMContextEntity {
    fileprivate var isToolCallResponse: Bool {
        if case .toolCallResponse = role {
            true
        } else {
            false
        }
    }
}
