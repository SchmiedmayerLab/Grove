//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveKeychainStorage
import GroveLLM
import GroveLLMOpenAI
@testable import GroveLLMOpenAIRealtime
import Testing


@MainActor
@Suite("Realtime Session Lifecycle")
struct LLMOpenAIRealtimeSessionLifecycleTests {
    @Test("Finishing the last generation cancels its tool and restores ready state")
    func finishesLastGeneration() async {
        let session = session()
        let tool = waitingTask()
        defer { tool.cancel() }
        session.registerGeneration("generation")
        session.toolTasks["response"] = .init(generationId: "generation", task: tool)
        session.state = .callingTools

        session.finishGeneration("generation")

        #expect(tool.isCancelled)
        #expect(session.activeGenerations.isEmpty)
        #expect(session.toolTasks.isEmpty)
        #expect(session.state == .ready)
        await tool.value
    }

    @Test("Finishing one generation preserves another generation's running tool")
    func preservesOtherGeneration() async {
        let session = session()
        let first = waitingTask()
        let second = waitingTask()
        defer {
            first.cancel()
            second.cancel()
        }
        session.registerGeneration("first-generation")
        session.registerGeneration("second-generation")
        session.toolTasks["first-response"] = .init(generationId: "first-generation", task: first)
        session.toolTasks["second-response"] = .init(generationId: "second-generation", task: second)
        session.state = .callingTools

        session.finishGeneration("first-generation")

        #expect(first.isCancelled)
        #expect(!second.isCancelled)
        #expect(session.activeGenerations == ["second-generation"])
        #expect(Set(session.toolTasks.keys) == ["second-response"])
        #expect(session.state == .callingTools)

        session.finishGeneration("second-generation")
        #expect(second.isCancelled)
        #expect(session.state == .ready)
        await first.value
        await second.value
    }

    @Test("Stopping listeners preserves the caller's loading or error state", arguments: [false, true])
    func stopsEventHandling(preservesError: Bool) async throws {
        let session = session()
        let expectedState: LLMState = preservesError ? .error(error: LLMOpenAIError.invalidRequest) : .loading
        session.state = expectedState
        let handlingId = session.eventHandlingId
        let transcripts = session.transcripts
        let listener = waitingTask()
        let tool = waitingTask()
        defer {
            listener.cancel()
            tool.cancel()
        }
        session.eventTask = listener
        session.registerGeneration("generation")
        session.toolTasks["response"] = .init(generationId: "generation", task: tool)
        session.assistantTranscripts.consume(
            .assistantTranscriptDelta(.init(responseId: "response", itemId: "assistant-item", contentIndex: 0, delta: "Partial")),
            context: &session.context
        )
        let unrelated = LLMContextEntity(role: .assistant, content: "Another response", complete: false)
        session.context.append(unrelated)

        session.stopEventHandling()

        #expect(session.state == expectedState)
        #expect(session.eventHandlingId != handlingId)
        #expect(session.transcripts !== transcripts)
        #expect(listener.isCancelled)
        #expect(tool.isCancelled)
        #expect(session.eventTask == nil)
        #expect(session.activeGenerations.isEmpty)
        #expect(session.toolTasks.isEmpty)
        #expect(try #require(session.context.first).complete)
        #expect(session.context.first?.content == "Partial")
        #expect(session.context.last == unrelated)
        await listener.value
        await tool.value
    }

    @Test("Public cancellation makes the session eligible to reconnect")
    func cancelResetsSession() async throws {
        let session = session()
        let tool = waitingTask()
        defer { tool.cancel() }
        session.registerGeneration("generation")
        session.toolTasks["response"] = .init(generationId: "generation", task: tool)
        session.state = .callingTools

        session.cancel()
        let deadline = ContinuousClock.now + .seconds(2)
        while session.state != .uninitialized, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(session.state == .uninitialized)
        #expect(session.toolTasks.isEmpty)
        #expect(session.activeGenerations.isEmpty)
        #expect(tool.isCancelled)
        await tool.value
    }

    private func session() -> LLMOpenAIRealtimeSession {
        let platform = LLMOpenAIRealtimePlatform(configuration: .init(authToken: .constant("unused-test-token")))
        return LLMOpenAIRealtimeSession(
            platform,
            schema: .init(parameters: .init(modelType: .gptRealtime, systemPrompt: nil)),
            keychainStorage: KeychainStorage()
        )
    }

    private func waitingTask() -> Task<Void, Never> {
        Task {
            // A bounded fallback keeps a broken cancellation path from hanging the test process.
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
