//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import Grove
@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import Testing


/// A tool with an unmistakable return value, so a model either called it or it didn't.
private struct GatewayTestFunction: LLMTool {
    let name = "perform_test"
    let description = "Performs a test and returns the value that proves the function was called"

    func execute() async throws -> String? {
        "The value to return to ensure the test was succesful is \"abcdefghijklmnopqrstuvwxyz\""
    }
}


/// Exercises a real OpenAI-compatible gateway end to end.
///
/// A gateway is the case ``LLMOpenAIAPIModePolicy/fixed(_:)`` exists for, and the failure it guards against is not
/// visible against `api.openai.com`: the gateway answers `/v1/responses` but cannot stream it, so only the fixed
/// chat-completions policy produces working inference.
///
/// Set `GROVE_GATEWAY_URL` and `GROVE_GATEWAY_TOKEN` to run these; without them the suite is skipped, so CI stays
/// hermetic.
@Suite(
    "LLM OpenAI Gateway Inference (Live)",
    .disabled(
        if: ProcessInfo.processInfo.environment["GROVE_GATEWAY_TOKEN"]?.isEmpty ?? true,
        "Set GROVE_GATEWAY_URL and GROVE_GATEWAY_TOKEN to run the live gateway tests"
    )
)
final class LLMOpenAIGatewayInferenceTests {
    /// Models the gateway serves, one per upstream vendor, to prove a single policy covers a mixed catalogue.
    static let models: [OpenAIPlatformDefinition.ModelType] = ["gpt-5.4", "claude-opus-4-7"]

    private var platformTask: Task<Void, Never>?

    @MainActor
    @Test("Every gateway model streams a response over the fixed chat-completions policy", arguments: models)
    func streamsOverChatCompletions(modelType: OpenAIPlatformDefinition.ModelType) async throws {
        let session = try makeSession(modelType: modelType, apiMode: .fixed(.chatCompletions))
        session.context.append(userMessage: "Reply with exactly the word: ok")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(!output.isEmpty, "\(modelType.rawValue) produced no output")
        #expect(output.lowercased().contains("ok"))
        #expect(session.state == .ready)
        // The answer is written back as a single completed assistant entity.
        let assistant = session.context.filter { $0.role == .assistant }
        #expect(assistant.count == 1)
        #expect(assistant.first?.complete == true)
    }

    @MainActor
    @Test("A multi-turn conversation keeps its history across turns", arguments: models)
    func multiTurnKeepsHistory(modelType: OpenAIPlatformDefinition.ModelType) async throws {
        let session = try makeSession(modelType: modelType, apiMode: .fixed(.chatCompletions))
        session.context.append(userMessage: "My favourite number is 7. Reply with just: noted")
        for try await _ in try await session.generate() { }

        session.context.append(userMessage: "What is my favourite number? Reply with the digit only.")
        var second = ""
        for try await piece in try await session.generate() {
            second.append(piece)
        }

        #expect(second.contains("7"), "\(modelType.rawValue) lost the earlier turn: \(second)")
    }

    @MainActor
    @Test("A tool is offered, called, and its output fed back", arguments: models)
    func functionCallingRoundTrips(modelType: OpenAIPlatformDefinition.ModelType) async throws {
        let session = try makeSession(modelType: modelType, apiMode: .fixed(.chatCompletions)) {
            GatewayTestFunction()
        }
        session.context.append(userMessage: "Call the perform_test function and tell me the value it returns.")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output.contains("abcdefghijklmnopqrstuvwxyz"), "\(modelType.rawValue) did not use the tool: \(output)")
    }

    /// The per-model policy would route `gpt-5.4` to `/v1/responses`, which this gateway cannot stream.
    ///
    /// Recorded as an expectation rather than a hard assertion: a gateway that later fixes its Responses streaming
    /// should not turn this suite red.
    @MainActor
    @Test("The per-model policy works once the streamed request falls back to a plain one")
    func perModelPolicySucceedsViaTheFallback() async throws {
        let session = try makeSession(modelType: "gpt-5.4", apiMode: .perModel)
        session.context.append(userMessage: "Reply with exactly the word: ok")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(!output.isEmpty, "the gateway cannot stream /v1/responses, so the fallback has to carry this")
        #expect(session.context.contains { $0.role == .assistant })
    }

    @MainActor
    @Test("Without the fallback, the per-model policy fails on this gateway")
    func perModelPolicyNeedsTheFallbackHere() async throws {
        let session = try makeSession(modelType: "gpt-5.4", apiMode: .perModel, streamingFallback: false)
        #expect(session.apiMode == .responses, "gpt-5.4 should derive to the Responses API under .perModel")

        session.context.append(userMessage: "Reply with exactly the word: ok")
        do {
            for try await _ in try await session.generate() {}
            Issue.record("Gateway now streams the Responses API — the fixed policy and the fallback may be moot here.")
        } catch {
            // Expected: the gateway answers a streamed `/v1/responses` request with a 500, and nothing catches it.
        }
    }

    @MainActor
    private func makeSession(
        modelType: OpenAIPlatformDefinition.ModelType,
        apiMode: LLMOpenAIAPIModePolicy,
        streamingFallback: Bool = true,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) throws -> LLMOpenAISession {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(URL(string: environment["GROVE_GATEWAY_URL"] ?? "https://aiapi-prod.stanford.edu/v1"))
        let token = try #require(environment["GROVE_GATEWAY_TOKEN"])

        let platform = LLMOpenAIPlatform(
            configuration: .init(serverUrl: url, authToken: .constant(token), apiMode: apiMode, streamingFallback: streamingFallback)
        )
        let runner = LLMRunner { platform }
        withDependencyResolution { runner }
        platformTask = Task { await platform.run() }

        return platform(
            with: LLMOpenAISchema(parameters: .init(modelType: modelType), injectIntoContext: true, functions)
        )
    }

    deinit {
        platformTask?.cancel()
    }
}
