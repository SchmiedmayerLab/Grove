//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Atomics
import Foundation
import GroveFoundation
import GroveLLM
@testable import GroveLLMOpenAI
import Observation
import Testing


private struct StateTestTool: LLMTool {
    let name = "state_test"
    let description = "Checks session state during execution"
    let perform: @Sendable () async throws -> String?

    func execute() async throws -> String? {
        try await perform()
    }
}


@Observable
private final class ToolStateSession: ToolCallLLMSession {
    static let logger = Logger(subsystem: "org.grovealliance", category: "LLMToolCancellationStateTests")
    let toolCallCompletionState = LLMState.ready
    let toolCallCounter = ManagedAtomic<Int>(0)

    @MainActor var state: LLMState = .loading
    @MainActor var context = LLMContext()

    @MainActor init() {}

    func generate() async throws -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() {}
}


@MainActor
@Suite("LLM Tool Cancellation State")
struct LLMToolCancellationStateTests {
    private enum ToolFailure: Error {
        case execution
    }

    @Test("A cancelled tool finishing after a reconnect cannot restore ready state", arguments: [false, true])
    func cancelledToolFinishes(throwsError: Bool) async {
        let session = ToolStateSession()
        let tool = StateTestTool {
            #expect(await session.state == .callingTools)
            withUnsafeCurrentTask { $0?.cancel() }
            // Reconnecting has replaced the old tool's state before that tool finishes.
            await MainActor.run { session.state = .loading }
            if throwsError {
                throw ToolFailure.execution
            }
            return "late result"
        }
        let task = Task {
            try await session.callFunction(
                availableFunctions: [tool.name: tool],
                functionCallArgs: .init(name: tool.name, id: "call-1", arguments: "{}"),
                failureHandling: .throwError
            )
        }
        _ = await task.result
        #expect(session.state == .loading)
        #expect(session.toolCallCounter.load(ordering: .sequentiallyConsistent) == 0)
    }

    @Test("Already cancelled work cannot enter calling-tools state")
    func cancelledBeforeToolStarts() async throws {
        let session = ToolStateSession()
        let tool = StateTestTool {
            #expect(await session.state == .loading)
            return "result"
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.callFunction(
                availableFunctions: [tool.name: tool],
                functionCallArgs: .init(name: tool.name, id: "call-1", arguments: "{}"),
                failureHandling: .throwError
            )
        }
        _ = try await task.value
        #expect(session.state == .loading)
        #expect(session.toolCallCounter.load(ordering: .sequentiallyConsistent) == 0)
    }

    @Test("A cancelled idle check cannot overwrite the replacement session state")
    func cancelledIdleCheck() async {
        let session = ToolStateSession()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await session.checkForActiveToolCalls()
        }
        await task.value
        #expect(session.state == .loading)
    }
}
