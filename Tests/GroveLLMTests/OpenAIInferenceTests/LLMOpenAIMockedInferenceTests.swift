//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveLLM
@testable import GroveLLMOpenAI
import OpenAPIRuntime
import Synchronization
import Testing


/// A tool that fails with a cancellation error while its generation is still running.
private struct SelfCancellingTool: LLMTool {
    let name = "cancel_itself"
    let description = "Fails with a cancellation error of its own"

    func execute() async throws -> String? {
        throw CancellationError()
    }
}


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
            try builder.appendUsage()
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
    @Test("An interrupted chat stream preserves partial text and skips pending tool calls")
    func interruptedChatStream() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini), injectIntoContext: true) {
            LLMOpenAITestFunction()
        }
        let client = MockChatClient()
        var requests = 0
        client.createChatCompletionHandler = { _ in
            requests += 1
            var builder = ChatResponseBuilder()
            guard requests == 1 else {
                builder.done()
                return builder.toChatOutput()
            }
            try builder.append(text: "partial")
            try builder.append(functionName: LLMOpenAITestFunction().name, arguments: "{}")
            return builder.toChatOutput()
        }
        let session = try initTestLLMSession(schema)
        session.context.append(userMessage: "Hello!")
        session.openAiClient = client
        var received = ""
        do {
            for try await delta in try await session.generate() {
                received.append(delta)
            }
            Issue.record("Expected an interrupted chat stream")
        } catch let error as LLMOpenAIError {
            #expect(error == .generationError)
        }
        #expect(requests == 1)
        #expect(received == "partial")
        #expect(session.context.last?.role == .assistant)
        #expect(session.context.last?.content == "partial")
        #expect(!session.context.contains { if case .toolCalls = $0.role { true } else { false } })
    }

    @MainActor
    @Test("A chat stream at the output limit is incomplete, keeps its text and runs no pending tool")
    func truncatedChatStream() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini)) {
            LLMOpenAITestFunction()
        }
        let client = MockChatClient()
        let requests = Mutex(0)
        client.createChatCompletionHandler = { _ in
            requests.withLock { $0 += 1 }
            var builder = ChatResponseBuilder()
            try builder.append(text: "Once upon")
            try builder.append(functionName: LLMOpenAITestFunction().name, arguments: "{}")
            builder.appendFinish(reason: "length")
            try builder.appendUsage()
            builder.done()
            return builder.toChatOutput()
        }
        let session = try initTestLLMSession(schema)
        session.context.append(userMessage: "Hello!")
        session.openAiClient = client

        var text = ""
        var results: [LLMRequestResult] = []
        var final: LLMGenerationResult?
        for try await event in try await session.generateEvents() {
            switch event {
            case .textDelta(let delta): text.append(delta)
            case .requestFinished(let result): results.append(result)
            case .finished(let result): final = result
            }
        }
        #expect(text == "Once upon")
        #expect(results.map(\.status) == [.incomplete])
        #expect(results.first?.reason == .outputLimit)
        #expect(results.first?.model == "grove-mock")
        #expect(final == .init(status: .incomplete, attempts: 1, usage: .init(inputTokens: 3, outputTokens: 2)))
        #expect(requests.withLock { $0 } == 1)
        #expect(!session.context.contains { if case .toolCallResponse = $0.role { true } else { false } })
    }

    @MainActor
    @Test("Cancelling one reader leaves another generation on the same session active", .timeLimit(.minutes(1)))
    func simultaneousReaders() async throws {
        let session = try initTestLLMSession(LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini)))
        session.context.append(userMessage: "Hello!")
        let client = MockChatClient()
        let calls = Mutex(0)
        let (started, signal) = AsyncStream<Int>.makeStream()
        let (release, gate) = AsyncStream<Void>.makeStream()
        let (stopped, stop) = AsyncStream<Void>.makeStream()
        client.createChatCompletionHandler = { _ in
            let call = calls.withLock {
                $0 += 1
                return $0
            }
            signal.yield(call)
            if call == 1 {
                // Outlasts the time limit unless cancelling the first reader stops this request.
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    stop.yield()
                    throw error
                }
            } else {
                for await _ in release { break }
            }
            var builder = ChatResponseBuilder()
            try builder.append(text: "survived")
            builder.done()
            return builder.toChatOutput()
        }
        session.openAiClient = client
        var starts = started.makeAsyncIterator()
        let first = try await session.generateEvents()
        let reader = Task { for try await _ in first {} }
        #expect(await starts.next() == 1)
        let second = try await session.generateEvents()
        #expect(await starts.next() == 2)
        reader.cancel()
        _ = await reader.result
        var stops = stopped.makeAsyncIterator()
        #expect(await stops.next() != nil)
        gate.finish()
        var events: [LLMGenerationEvent] = []
        for try await event in second { events.append(event) }
        #expect(events.first == .textDelta("survived"))
        #expect(events.last == .finished(.init(status: .completed, attempts: 1, usage: .init())))
        #expect(calls.withLock { $0 } == 2)
    }

    @MainActor
    @Test("A tool that throws a cancellation error of its own is answered and the generation continues")
    func toolCancellationErrorIsAnswered() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini), injectIntoContext: true) {
            SelfCancellingTool()
        }
        let session = try initTestLLMSession(schema)
        session.context.append(userMessage: "Hello!")
        let client = MockChatClient()
        let requests = Mutex(0)
        client.createChatCompletionHandler = { _ in
            let request = requests.withLock {
                $0 += 1
                return $0
            }
            var builder = ChatResponseBuilder()
            if request == 1 {
                try builder.append(functionName: SelfCancellingTool().name, arguments: "{}")
            } else {
                try builder.append(text: "Answered.")
            }
            builder.done()
            return builder.toChatOutput()
        }
        session.openAiClient = client

        var final: LLMGenerationResult?
        for try await event in try await session.generateEvents() {
            if case .finished(let result) = event {
                final = result
            }
        }
        #expect(requests.withLock { $0 } == 2)
        #expect(final?.status == .completed)
        #expect(session.context.contains { if case .toolCallResponse = $0.role { true } else { false } })
    }

    @MainActor
    @Test("An unread event stream overflows before a pending tool can run")
    func overflowStopsPendingTool() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini)) { LLMOpenAITestFunction() }
        let session = try initTestLLMSession(schema)
        session.context.append(userMessage: "Hello!")
        let client = MockChatClient()
        let calls = Mutex(0)
        client.createChatCompletionHandler = { _ in
            calls.withLock { $0 += 1 }
            var builder = ChatResponseBuilder()
            try builder.append(functionName: LLMOpenAITestFunction().name, arguments: "{}")
            for _ in 0..<257 { try builder.append(text: "x") }
            builder.done()
            return builder.toChatOutput()
        }
        session.openAiClient = client
        let stream = try await session.generateEvents()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !session.generations.withLock({ $0.isEmpty }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(session.generations.withLock { $0.isEmpty })
        await #expect(throws: LLMGenerationStreamError.bufferOverflow) {
            for try await _ in stream {}
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(!session.context.contains { if case .toolCallResponse = $0.role { true } else { false } })
    }

    @MainActor
    @Test("Cancelling iteration during a stream stops the generation before its pending tool runs", .timeLimit(.minutes(1)))
    func cancellationDuringStreamStopsPendingTool() async throws {
        let schema = LLMOpenAISchema(parameters: .init(modelType: .gpt4o_mini)) { LLMOpenAITestFunction() }
        let session = try initTestLLMSession(schema)
        session.context.append(userMessage: "Hello!")
        let client = MockChatClient()
        let calls = Mutex(0)
        let (release, gate) = AsyncStream<Void>.makeStream()
        client.createChatCompletionHandler = { _ in
            calls.withLock { $0 += 1 }
            var head = ChatResponseBuilder()
            try head.append(text: "partial")
            var tail = ChatResponseBuilder()
            try tail.append(functionName: LLMOpenAITestFunction().name, arguments: "{}")
            tail.done()
            let (first, rest) = (head.httpBody(), tail.httpBody())
            let chunks = AsyncThrowingStream<HTTPBody.ByteChunk, any Error> { continuation in
                let task = Task {
                    do {
                        for try await chunk in first { continuation.yield(chunk) }
                        for await _ in release { break }
                        for try await chunk in rest { continuation.yield(chunk) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return .ok(.init(body: .text_event_hyphen_stream(HTTPBody(chunks, length: .unknown))))
        }
        session.openAiClient = client

        let stream = try await session.generateEvents()
        let (received, signal) = AsyncStream<Void>.makeStream()
        let reader = Task {
            for try await event in stream where event == .textDelta("partial") {
                signal.yield()
            }
        }
        var receipts = received.makeAsyncIterator()
        #expect(await receipts.next() != nil)
        reader.cancel()
        _ = await reader.result
        gate.finish()
        while !session.generations.withLock({ $0.isEmpty }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(!session.context.contains { if case .toolCalls = $0.role { true } else { false } })
        #expect(!session.context.contains { if case .toolCallResponse = $0.role { true } else { false } })
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
                try builder.appendUsage()
                builder.done()
            }
            
            chatCompletionCalls += 1
            return builder.toChatOutput()
        }
        
        var oneShot = ""
        var requests: [LLMRequestResult] = []
        var final: LLMGenerationResult?
        for try await event in try await llmSession.generateEvents() {
            #expect(final == nil)
            switch event {
            case .textDelta(let text): oneShot.append(text)
            case .requestFinished(let request): requests.append(request)
            case .finished(let result): final = result
            }
        }
        #expect(requests.map(\.request) == [1, 2])
        #expect(requests.map(\.attempt) == [1, 1])
        #expect(requests.map(\.status) == [.completed, .completed])
        #expect(requests.last?.usage == .init(inputTokens: 3, outputTokens: 2))
        #expect(final == .init(status: .completed, attempts: 2, usage: .init()))

        // Expect that the chatCompletionHandler was called 2 times: first for the function call, second time for text generation
        #expect(chatCompletionCalls == 2, "Chat completion handler was not called twice")
        // Expect that the (mocked) LLM returned an answer
        #expect(oneShot == "Function should have been called!")
    }
}
