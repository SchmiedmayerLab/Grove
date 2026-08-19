//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLM
@testable import GroveLLMOpenAI
import Testing


@Suite("LLM OpenAI Inference Tests (Mocked API)")
class LLMOpenAIMockedInferenceTests: LLMOpenAIInferenceTests {
    @MainActor
    @Test
    func testMockedOpenAIInference() async throws {
        let schema = LLMOpenAISchema(
            parameters: .init(modelType: .gpt4o_mini)
        ) { }
        
        var context = LLMContext()
        context.append(userMessage: "Hello!")
        
        let mockClient = MockChatClient()
        mockClient.createChatCompletionHandler = { _ in
            var builder = ChatResponseBuilder()
            try builder.append(text: "Hello ")
            try builder.append(text: "world!")
            builder.done()
            
            return builder.toChatOutput()
        }
        
        let llmSession = try initTestLLMSession(schema)
        llmSession.context = context
        llmSession.openAiClient = mockClient
        
        var oneShot = ""
        for try await stringPiece in try await llmSession.generate() {
            oneShot.append(stringPiece)
        }
        
        #expect(oneShot == "Hello world!")
    }

    @MainActor
    @Test("Typed request failures reach the caller unchanged")
    func typedRequestFailuresReachTheCaller() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini))
        let mockClient = MockChatClient()
        mockClient.createChatCompletionHandler = { _ in
            throw LLMOpenAIError.invalidRequest
        }

        let llmSession = try initTestLLMSession(schema)
        llmSession.context.append(userMessage: "Hello!")
        llmSession.openAiClient = mockClient

        do {
            for try await _ in try await llmSession.generate() { }
            Issue.record("Expected the typed request error to be thrown")
        } catch let error as LLMOpenAIError {
            #expect(error == .invalidRequest)
        }
    }
    
    @MainActor
    @Test
    func testMockedOpenAIFunctionCalling() async throws {
        var context = LLMContext()
        context.append(userMessage: "Hello!")
        
        let mockClient = MockChatClient()
        let schema = LLMOpenAISchema(
            parameters: .init(modelType: .gpt4o_mini)
        ) {
            LLMOpenAITestFunction()
        }
        
        let llmSession = try initTestLLMSession(schema)
        llmSession.context = context
        llmSession.openAiClient = mockClient
        
        var chatCompletionCalls = 0
        mockClient.createChatCompletionHandler = { input in
            var builder = ChatResponseBuilder()
            
            if chatCompletionCalls == 0 {
                try builder.append(functionName: LLMOpenAITestFunction().name, arguments: "{}")
                builder.done()
            } else {
                if case let .json(inputBody) = input.body {
                    // The function call's result must come back as a structured tool message.
                    let toolMessages = inputBody.value2.messages.compactMap { message -> String? in
                        guard case .ChatCompletionRequestToolMessage(let toolMessage) = message,
                              case .case1(let content) = toolMessage.content else {
                            return nil
                        }
                        return content
                    }
                    #expect(toolMessages.contains {
                        $0.contains(#"The value to return to ensure the test was succesful is "abcdefghijklmnopqrstuvwxyz""#)
                    })
                } else {
                    Issue.record("Failed to parse JSON input body")
                }
                
                try builder.append(text: "Function should have been called!")
                builder.done()
            }
            
            chatCompletionCalls += 1
            return builder.toChatOutput()
        }
        
        var oneShot = ""
        for try await stringPiece in try await llmSession.generate() {
            oneShot.append(stringPiece)
        }
        
        // Expect that the chatCompletionHandler was called 2 times: first for the function call, second time for text generation
        #expect(chatCompletionCalls == 2, "Chat completion handler was not called twice")
        // Expect that the (mocked) LLM returned an answer
        #expect(oneShot == "Function should have been called!")
    }
}
