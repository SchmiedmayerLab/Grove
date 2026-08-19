//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import os
import SwiftUI
import Testing

// To enable tests that require an OpenAI API key, pass it on the command line — the test plan forwards it into the
// test process, so the key stays out of the tracked plan file:
//
//   xcodebuild test -scheme Grove-Tests -testPlan GroveLLM -destination 'platform=macOS' \
//     OPENAI_API_TOKEN="$(security find-generic-password -s openai-api-key-grove -w)"
@Suite("LLM OpenAI Inference Tests (Using API Key)",
       .disabled(
        if: ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"] == nil ||
        ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"]?.isEmpty ?? true,
        "Skip test if no OPEN AI API Token is set as an environment variable"
       )
)
class LLMOpenAIInferenceTests {
    struct LLMOpenAITestFunction: LLMTool {
        let name: String = "perform_test"
        let description: String = "Performs a tests and returns a specific value to ensure this function has been called"
        
        
        func execute() async throws -> String? {
            "The value to return to ensure the test was succesful is \"abcdefghijklmnopqrstuvwxyz\""
        }
    }
    
    
    static let logger = Logger(subsystem: "org.grovealliance", category: "GroveLLMInferenceTests")
    
    private var llmOpenAIPlatform: LLMOpenAIPlatform?
    private var task: Task<Void, Never>?
    
    
    @MainActor
    func initTestLLMSession(_ schema: LLMOpenAISchema) throws -> LLMOpenAISession {
        guard llmOpenAIPlatform == nil else {
            return try #require(llmOpenAIPlatform).callAsFunction(with: schema)
        }
        
        let llmOpenAIPlatform = LLMOpenAIPlatform(configuration: LLMOpenAIPlatformConfiguration(authToken: .constant("mocked-token")))
        let runner = LLMRunner {
            llmOpenAIPlatform
        }
        withDependencyResolution {
            runner
        }
        
        self.task = Task {
            await llmOpenAIPlatform.run()
            Issue.record("The LLM OpenAI platform should not exit its run loop during the module lifetime.")
        }
        
        self.llmOpenAIPlatform = llmOpenAIPlatform
        return llmOpenAIPlatform(with: schema)
    }
    
    
    @MainActor
    @Test
    func testOpenAIFunctionCalling() async throws {
        guard let openAIToken = ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"] else {
            return
        }
        
        let schema = LLMOpenAISchema(
            parameters: .init(modelType: .gpt4_1_mini, overwritingAuthToken: .constant(openAIToken))
        ) {
            LLMOpenAITestFunction()
        }
        
        let llmSession = try initTestLLMSession(schema)
        llmSession.context.append(userMessage: "Hello! Return me the value needed for this test")

        var oneShot = ""
        for try await stringPiece in try await llmSession.generate() {
            oneShot.append(stringPiece)
        }
        
        Self.logger.debug(
            """
            LLMOpenAIInferenceTests: Received GPT response from OpenAI API call, during testOpenAIFunctionCalling()
            Response: \(oneShot)
            """
        )
        
        try #require(!oneShot.isEmpty)
        #expect(oneShot.contains("abcdefghijklmnopqrstuvwxyz"))
    }
}
