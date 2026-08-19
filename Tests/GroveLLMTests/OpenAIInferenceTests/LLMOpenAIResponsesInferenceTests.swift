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
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


@Suite("LLM OpenAI Responses API Inference Tests (Mocked API)")
class LLMOpenAIResponsesInferenceTests: LLMOpenAIInferenceTests {
    /// A 1×1 image, created without touching the file system.
    static func testImage() -> LLMContextEntity._PlatformImage {
        #if canImport(UIKit)
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #else
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
        #endif
    }

    @MainActor
    @Test("Streamed text deltas are yielded and injected into the context")
    func streamsTextOutput() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.outputTextDelta("Hello ")
            builder.outputTextDelta("world!")
            builder.outputTextDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output == "Hello world!")
        let assistantMessages = session.context.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.content == "Hello world!")
        #expect(assistantMessages.first?.complete == true)
        #expect(session.state == .ready)
    }

    @MainActor
    @Test("Reasoning summaries land in thinking entities that share the interaction of the response")
    func streamsReasoningSummaries() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Why?")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.reasoningSummaryPartAdded()
            builder.reasoningSummaryDelta("Considering ")
            builder.reasoningSummaryDelta("the options.")
            builder.reasoningSummaryPartDone()
            builder.outputTextDelta("Because.")
            builder.outputTextDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        for try await _ in try await session.generate() { }

        let thinking = try #require(session.context.first { $0.role == .assistantThinking })
        #expect(thinking.content == "Considering the options.")
        #expect(thinking.complete)

        // Thinking and the answer it produced belong to the same interaction, so the UI can group them.
        let assistant = try #require(session.context.first { $0.role == .assistant })
        #expect(thinking.interactionId != nil)
        #expect(thinking.interactionId == assistant.interactionId)
    }

    @MainActor
    @Test("A thinking placeholder that never receives a summary is not left dangling")
    func discardsEmptyThinkingPlaceholder() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hi")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.outputTextDelta("Hi!")
            builder.outputTextDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        for try await _ in try await session.generate() { }

        // The placeholder opened by `response.created` never produced content, so it must vanish entirely —
        // otherwise every non-reasoning response would render a spurious "Thought for 0 sec" row.
        #expect(!session.context.contains { $0.role == .assistantThinking })
    }

    @MainActor
    @Test("A requested tool is executed and its output is fed back in a second request")
    func executesFunctionCalls() async throws {
        let session = try makeSession(modelType: .gpt5_mini) {
            LLMOpenAITestFunction()
        }
        session.context.append(userMessage: "Run the test")

        let client = MockChatClient()
        var requestCount = 0
        var secondRequestInput: Components.Schemas.CreateResponse?
        client.createResponseHandler = { input in
            defer { requestCount += 1 }
            var builder = ResponsesStreamBuilder()
            builder.created()
            if requestCount == 0 {
                builder.functionCall(name: LLMOpenAITestFunction().name, arguments: "{}")
            } else {
                if case let .json(body) = input.body {
                    secondRequestInput = body
                }
                builder.outputTextDelta("Done.")
                builder.outputTextDone()
            }
            builder.completed(responseId: "resp_\(requestCount)")
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(requestCount == 2)
        #expect(output == "Done.")

        let toolCalls = try #require(session.context.first { $0.isToolCalls })
        guard case .toolCalls(let calls) = toolCalls.role else {
            Issue.record("Expected a toolCalls entity")
            return
        }
        #expect(calls.map(\.name) == [LLMOpenAITestFunction().name])

        let response = try #require(session.context.first { $0.isToolCallResponse })
        #expect(response.content.contains("abcdefghijklmnopqrstuvwxyz"))

        // The follow-up request continues the server-side conversation, and carries only the tool output —
        // not the model's own turn, which the server already holds.
        let body = try #require(secondRequestInput)
        #expect(body.value2.previous_response_id == "resp_0")
        guard case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }
        #expect(items.count == 1)
        guard case .Item(.FunctionCallOutputItemParam(let output)) = items[0] else {
            Issue.record("Expected the tool output to be the only new input item, got \(items[0])")
            return
        }
        #expect(output.call_id == "call_mock")
    }

    @MainActor
    @Test("A failed response surfaces as an error and leaves no incomplete thinking entity behind")
    func surfacesResponseFailure() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.reasoningSummaryPartAdded()
            builder.reasoningSummaryDelta("Hmm")
            builder.failed(message: "the model is on fire")
            return builder.output()
        }
        session.openAiClient = client

        await #expect(throws: (any Error).self) {
            for try await _ in try await session.generate() { }
        }

        #expect(!session.context.contains { $0.role == .assistantThinking && !$0.complete })
    }

    @MainActor
    @Test("Malformed and unrecognized events are skipped rather than aborting the stream")
    func toleratesUnknownEvents() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.unknownEvent()
            builder.outputTextDelta("Still ")
            builder.malformedEvent()
            builder.messageOutputItemDone()
            builder.outputTextDelta("here.")
            builder.outputTextDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }
        #expect(output == "Still here.")
    }

    @MainActor
    @Test("System prompts are hoisted into `instructions`, and a reasoning model requests summaries")
    func buildsRequestFromSchema() async throws {
        let session = try makeSession(modelType: .gpt5_mini, systemPrompt: "You are terse.")
        session.context.append(systemMessage: "You are terse.", to: .leadingSystemMessages)
        session.context.append(userMessage: "Hello!")


        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body else {
            Issue.record("Expected a JSON body")
            return
        }

        #expect(body.value3.instructions == "You are terse.")
        #expect(body.value3.stream == true)
        #expect(body.value2.previous_response_id == nil)
        #expect(body.value2.reasoning?.summary == .auto)

        // The system message goes into `instructions`, so only the user message remains as an input item.
        guard case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }
        #expect(items.count == 1)
    }

    @MainActor
    @Test("A non-reasoning model does not request reasoning summaries")
    func omitsReasoningForNonReasoningModels() async throws {
        let session = try makeSession(modelType: .gpt5_chat)
        session.context.append(userMessage: "Hello!")

        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body else {
            Issue.record("Expected a JSON body")
            return
        }
        #expect(body.value2.reasoning == nil)
    }


    @MainActor
    func makeSession(
        modelType: OpenAIPlatformDefinition.ModelType,
        systemPrompt: String? = nil,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) throws -> LLMOpenAISession {
        try initTestLLMSession(
            LLMOpenAISchema(
                parameters: .init(modelType: modelType, systemPrompt: systemPrompt),
                injectIntoContext: true,
                functions
            )
        )
    }
}


extension LLMContextEntity {
    fileprivate var isToolCalls: Bool {
        if case .toolCalls = role {
            true
        } else {
            false
        }
    }

    fileprivate var isToolCallResponse: Bool {
        if case .toolCallResponse = role {
            true
        } else {
            false
        }
    }
}
