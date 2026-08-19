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
import Testing


@Suite("LLM OpenAI API Mode")
final class LLMOpenAIAPIModeTests: LLMOpenAIInferenceTests {
    /// Keeps the gateway platform's run loop alive for as long as the test that started it.
    private var platformTask: Task<Void, Never>?

    @Test("Models decide the API under the per-model policy")
    func perModelPolicy() {
        #expect(LLMOpenAIAPIModePolicy.perModel.resolve(for: OpenAIPlatformDefinition.ModelType.gpt5_6) == .responses)
        #expect(LLMOpenAIAPIModePolicy.perModel.resolve(for: OpenAIPlatformDefinition.ModelType.gpt4o) == .chatCompletions)
    }

    @Test("A fixed policy overrides what the model itself declares")
    func fixedPolicyOverridesTheModel() {
        let gateway = LLMOpenAIAPIModePolicy.fixed(.chatCompletions)
        #expect(gateway.resolve(for: OpenAIPlatformDefinition.ModelType.gpt5_6) == .chatCompletions)
        #expect(gateway.resolve(for: OpenAIPlatformDefinition.ModelType.gpt4o) == .chatCompletions)
    }

    /// A model that would otherwise use the Responses API has to reach a gateway that only serves chat completions
    /// over `/v1/chat/completions`, since a request to `/v1/responses` would simply 404 there.
    @MainActor
    @Test("A gateway platform serves a Responses-API model over chat completions")
    func gatewayServesResponsesModelOverChatCompletions() async throws {
        let session = try makeGatewaySession(modelType: .gpt5_6)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createChatCompletionHandler = { _ in
            var builder = ChatResponseBuilder()
            try builder.append(text: "Hi from the gateway.")
            builder.done()
            return builder.toChatOutput()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output == "Hi from the gateway.")
        // Left unset, so the Responses API path would have trapped had it been taken.
        #expect(client.createResponseHandler == nil)
    }

    @MainActor
    private func makeGatewaySession(modelType: OpenAIPlatformDefinition.ModelType) throws -> LLMOpenAISession {
        let platform = LLMOpenAIPlatform(
            configuration: .init(
                serverUrl: try #require(URL(string: "https://gateway.example.edu/v1")),
                authToken: .constant("mocked-token"),
                apiMode: .fixed(.chatCompletions)
            )
        )
        let runner = LLMRunner {
            platform
        }
        withDependencyResolution {
            runner
        }
        // Without the platform's run loop, the inference task is queued and never picked up.
        platformTask = Task {
            await platform.run()
        }
        return platform(with: LLMOpenAISchema(parameters: .init(modelType: modelType), injectIntoContext: true))
    }

    deinit {
        platformTask?.cancel()
    }
}
