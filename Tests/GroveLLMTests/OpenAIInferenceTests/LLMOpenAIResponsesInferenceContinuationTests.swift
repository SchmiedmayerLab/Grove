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
import Testing


extension LLMOpenAIResponsesInferenceTests {
    @MainActor
    @Test("A refusal streams to the user exactly like output text")
    func surfacesRefusals() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Do something disallowed")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.refusalDelta("I can't ")
            builder.refusalDelta("help with that.")
            builder.refusalDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }
        #expect(output == "I can't help with that.")
        #expect(session.context.last?.role == .assistant)
        #expect(session.context.last?.complete == true)
    }

    @MainActor
    @Test("An incomplete response still commits the conversation for continuation")
    func handlesIncompleteResponses() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Write a novel")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.outputTextDelta("Once upon a ti")
            builder.incomplete(responseId: "resp_truncated")
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }
        #expect(output == "Once upon a ti")
        #expect(session.lastResponseId == "resp_truncated", "A truncated response remains the continuation point")
        #expect(session.state == .ready)
    }

    @MainActor
    @Test("An in-stream error event aborts the generation")
    func surfacesStreamErrors() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.errorEvent(message: "rate limited mid-stream")
            return builder.output()
        }
        session.openAiClient = client

        await #expect(throws: (any Error).self) {
            for try await _ in try await session.generate() { }
        }
        #expect(!session.context.contains { $0.role == .assistantThinking && !$0.complete })
    }

    @MainActor
    @Test("Without context injection, tokens only stream and the context receives no assistant text")
    func streamsWithoutContextInjection() async throws {
        let session = try initTestLLMSession(
            LLMOpenAISchema(parameters: .init(modelType: .gpt5_mini))  // injectIntoContext defaults to false
        )
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.reasoningSummaryPartAdded()
            builder.reasoningSummaryDelta("Working on it.")
            builder.reasoningSummaryPartDone()
            builder.outputTextDelta("Hello!")
            builder.outputTextDone()
            builder.completed()
            return builder.output()
        }
        session.openAiClient = client

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(output == "Hello!")
        // The stream is the only text channel, but thinking still lands in the context for the UI.
        #expect(!session.context.contains { $0.role == .assistant })
        let thinking = try #require(session.context.first { $0.role == .assistantThinking })
        #expect(thinking.content == "Working on it.")
        #expect(thinking.complete)
    }

    @MainActor
    @Test("An image entity becomes an input_image item in the request")
    func buildsImageInputItems() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "What is this?")
        let imageEntity = try #require(LLMContextEntity(
            _role: .user,
            image: Self.testImage(),
            format: .jpeg(compressionFactor: 0.8)
        ))
        session.context.append(imageEntity)

        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body, case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }
        let imageItems = items.compactMap { item -> String? in
            guard case .Item(.InputMessage(let message)) = item,
                  case .InputImageContent(let image) = message.content.first else {
                return nil
            }
            return image.image_url
        }
        #expect(imageItems.count == 1)
        #expect(imageItems.first?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @MainActor
    @Test("A failed request does not mark its input as delivered; the retry re-sends it")
    func failedRequestIsRetriedWithFullInput() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        let client = MockChatClient()
        var requestCount = 0
        var secondRequestInput: Components.Schemas.CreateResponse?
        client.createResponseHandler = { input in
            defer { requestCount += 1 }
            var builder = ResponsesStreamBuilder()
            builder.created()
            if requestCount == 0 {
                builder.failed(message: "transient upstream error")
            } else {
                if case let .json(body) = input.body {
                    secondRequestInput = body
                }
                builder.outputTextDelta("Recovered.")
                builder.outputTextDone()
                builder.completed()
            }
            return builder.output()
        }
        session.openAiClient = client

        await #expect(throws: (any Error).self) {
            for try await _ in try await session.generate() { }
        }

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }
        #expect(output == "Recovered.")

        // The failed request never committed its input; the retry starts fresh and carries the user message.
        let body = try #require(secondRequestInput)
        #expect(body.value2.previous_response_id == nil)
        guard case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }
        #expect(items.contains { item in
            if case .EasyInputMessage(let message) = item, message.role == .user {
                return true
            }
            return false
        })
    }

    @MainActor
    @Test("Replaying a history with parallel tool calls emits one function_call item per call")
    func multiToolCallReplay() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Check two things")
        session.context.append(
            toolCalls: [
                .init(id: "call_1", name: "check_a", arguments: "{}"),
                .init(id: "call_2", name: "check_b", arguments: "{}")
            ]
        )
        session.context.append(toolCallResponse: "a ok", for: "check_a", withId: "call_1")
        session.context.append(toolCallResponse: "b ok", for: "check_b", withId: "call_2")

        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body, case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }

        var functionCallIds: [String] = []
        var outputIds: [String] = []
        for item in items {
            if case .Item(.FunctionToolCall(let call)) = item {
                functionCallIds.append(call.call_id)
            } else if case .Item(.FunctionCallOutputItemParam(let output)) = item {
                outputIds.append(output.call_id)
            }
        }
        #expect(functionCallIds == ["call_1", "call_2"])
        #expect(outputIds == ["call_1", "call_2"], "Every output must find its call in the replayed history")
    }

    @MainActor
    @Test("Clearing the context starts a fresh server-side conversation")
    func clearingTheContextResetsTheConversation() async throws {
        let session = try makeSession(modelType: .gpt5_mini)
        session.context.append(userMessage: "Hello!")

        // A full successful round leaves the conversation held server-side.
        let client = MockChatClient()
        client.createResponseHandler = { _ in
            var builder = ResponsesStreamBuilder()
            builder.created()
            builder.outputTextDelta("Hi!")
            builder.outputTextDone()
            builder.completed(responseId: "resp_stale")
            return builder.output()
        }
        session.openAiClient = client
        for try await _ in try await session.generate() { }
        #expect(session.lastResponseId == "resp_stale")

        session.context.clear(keepLeadingSystemMessages: false)
        session.context.append(userMessage: "Let's start over.")

        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body else {
            Issue.record("Expected a JSON body")
            return
        }
        #expect(body.value2.previous_response_id == nil)
        guard case .case2(let items) = body.value3.input else {
            Issue.record("Expected a list of input items")
            return
        }
        #expect(items.count == 1, "The rebuilt conversation carries exactly the context as it now stands")
    }

    @MainActor
    @Test("A schema's functions are advertised as tools")
    func advertisesTools() async throws {
        let session = try makeSession(modelType: .gpt5_mini) {
            LLMOpenAITestFunction()
        }
        session.context.append(userMessage: "Hello!")

        let query = try await session.openAIResponsesQuery()
        guard case let .json(body) = query.body else {
            Issue.record("Expected a JSON body")
            return
        }
        let tools = try #require(body.value2.tools)
        #expect(tools.count == 1)
        guard case .function(let tool) = tools[0] else {
            Issue.record("Expected a function tool, got \(tools[0])")
            return
        }
        #expect(tool.name == LLMOpenAITestFunction().name)
    }
}
