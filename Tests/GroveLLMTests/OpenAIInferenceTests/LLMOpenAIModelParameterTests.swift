//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GeneratedOpenAIClient
@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import Testing


/// Covers the parameters a caller sets actually reaching the request, on whichever API the model takes.
///
/// Which path a model takes is decided for it — the four Chat Completions model ids go one way and everything else,
/// including the whole GPT-5 line, goes the other. So a parameter honoured on only one path is a bug the caller
/// cannot see: switching model changes whether their setting does anything, with nothing in the request, the logs,
/// or the response to say so. ``aResponseFormatIsSentOnEitherPath`` asserts both paths together for that reason.
@Suite("LLM OpenAI Model Parameters")
class LLMOpenAIModelParameterTests: LLMOpenAIInferenceTests {
    @MainActor
    @Test("A requested response format is sent, whichever API the model takes")
    func aResponseFormatIsSentOnEitherPath() async throws {
        // gpt-5 goes to the Responses API, gpt-4o to Chat Completions.
        let responsesSession = try makeParameterSession(modelType: .gpt5_mini, responseFormat: .jsonObject)
        responsesSession.context.append(userMessage: "Answer in JSON.")
        let chatSession = try makeParameterSession(modelType: .gpt4o, responseFormat: .jsonObject)
        chatSession.context.append(userMessage: "Answer in JSON.")

        guard case let .json(responsesBody) = try await responsesSession.openAIResponsesQuery(stream: false).body else {
            Issue.record("Expected a JSON body on the Responses path")
            return
        }
        guard case .ResponseFormatJsonObject = try #require(responsesBody.value2.text?.format) else {
            Issue.record("The Responses request has to carry the format under `text`, got \(String(describing: responsesBody.value2.text))")
            return
        }

        guard case let .json(chatBody) = try await chatSession.openAIChatQuery().body else {
            Issue.record("Expected a JSON body on the Chat Completions path")
            return
        }
        guard case .ResponseFormatJsonObject = try #require(chatBody.value2.response_format) else {
            Issue.record("The Chat Completions request has to carry `response_format`")
            return
        }
    }

    @MainActor
    @Test("A caller who asks for nothing sends nothing")
    func noResponseFormatMeansNoField() async throws {
        let session = try makeParameterSession(modelType: .gpt5_mini, responseFormat: nil)
        session.context.append(userMessage: "Hello!")

        guard case let .json(body) = try await session.openAIResponsesQuery(stream: false).body else {
            Issue.record("Expected a JSON body")
            return
        }
        #expect(body.value2.text == nil, "an unset format must not put an empty `text` on the request")
    }

    @MainActor
    private func makeParameterSession(
        modelType: OpenAIPlatformDefinition.ModelType,
        responseFormat: LLMOpenAIModelParameters.ResponseFormat?
    ) throws -> LLMOpenAISession {
        try initTestLLMSession(
            LLMOpenAISchema(
                parameters: .init(modelType: modelType),
                modelParameters: .init(responseFormat: responseFormat),
                injectIntoContext: true
            )
        )
    }
}
