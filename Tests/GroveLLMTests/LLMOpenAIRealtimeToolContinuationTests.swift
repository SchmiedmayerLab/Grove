//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLMOpenAI
@testable import GroveLLMOpenAIRealtime
import Testing


@MainActor
@Suite("Realtime Tool Continuations")
struct LLMOpenAIRealtimeToolContinuationTests {
    private enum ToolFailure: Error {
        case execution
        case output
    }

    @Test("All tool outputs precede one continuation with the original generation", arguments: [true, false])
    func multipleToolCalls(tracksGeneration: Bool) async throws {
        let generationId = tracksGeneration ? "generation-1" : nil
        var operations: [String] = []
        var continuedGenerations: [String?] = []
        try await LLMOpenAIRealtimeSession.continueToolResponse(response(generationId: generationId)) { call in
            operations.append("execute \(call.id ?? "missing")")
            return try output(for: call)
        } sendOutput: { output in
            operations.append("send \(output.functionID)")
        } requestNext: { generationId in
            operations.append("continue")
            continuedGenerations.append(generationId)
        }
        #expect(operations == ["execute first", "send first", "execute second", "send second", "continue"])
        #expect(continuedGenerations == [generationId])
    }

    @Test("Cancellation during execution prevents output and further tool calls")
    func cancellationDuringExecution() async {
        var operations: [String] = []
        let task = Task {
            try await LLMOpenAIRealtimeSession.continueToolResponse(response()) { call in
                operations.append("execute \(call.id ?? "missing")")
                // Cancel only this child task; a tool can return after its caller has been cancelled.
                withUnsafeCurrentTask { $0?.cancel() }
                return try output(for: call)
            } sendOutput: { output in
                operations.append("send \(output.functionID)")
            } requestNext: { _ in
                operations.append("continue")
            }
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(operations == ["execute first"])
    }

    @Test("A failed tool output prevents subsequent execution and continuation")
    func failedOutput() async {
        var operations: [String] = []
        await #expect(throws: ToolFailure.self) {
            try await LLMOpenAIRealtimeSession.continueToolResponse(response()) { call in
                operations.append("execute \(call.id ?? "missing")")
                return try output(for: call)
            } sendOutput: { output in
                operations.append("send \(output.functionID)")
                throw ToolFailure.output
            } requestNext: { _ in
                operations.append("continue")
            }
        }
        #expect(operations == ["execute first", "send first"])
    }

    @Test("A thrown execution error propagates without output or continuation")
    func failedExecution() async {
        var operations: [String] = []
        await #expect(throws: ToolFailure.self) {
            try await LLMOpenAIRealtimeSession.continueToolResponse(response()) { call in
                operations.append("execute \(call.id ?? "missing")")
                throw ToolFailure.execution
            } sendOutput: { output in
                operations.append("send \(output.functionID)")
            } requestNext: { _ in
                operations.append("continue")
            }
        }
        #expect(operations == ["execute first"])
    }

    private func response(generationId: String? = "generation-1") -> LLMRealtimeAudioEvent.Response {
        .init(
            id: "response-1",
            requestId: "request-1",
            generationId: generationId,
            status: .completed,
            functionCalls: [
                .init(name: "lookup", id: "first", arguments: "{}"),
                .init(name: "lookup", id: "second", arguments: "{}")
            ]
        )
    }

    private func output(for call: LLMOpenAIStreamResult.FunctionCall) throws -> ToolCallLLMSessionTypes.ToolCallResponse {
        .init(functionID: try #require(call.id), functionName: try #require(call.name), response: "result")
    }
}
