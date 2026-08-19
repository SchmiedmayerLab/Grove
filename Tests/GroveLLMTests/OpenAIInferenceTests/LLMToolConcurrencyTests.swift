//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLM
@testable import GroveLLMOpenAI
import Synchronization
import Testing


/// Echoes its arguments back after yielding, which is what makes a crossed argument observable.
///
/// The suspension inside `execute()` is the point: it hands the executor a chance to run another invocation, so an
/// implementation that kept arguments on the function itself would be overwritten before this call reads them back.
private struct SlowEchoFunction: LLMTool {
    let name = "echo_token"
    let description = "Echoes the token it is given"

    @Parameter(description: "The token to echo back")
    var token: String
    @Parameter(description: "An optional note")
    var note: String?

    func execute() async throws -> String? {
        try await Task.sleep(for: .milliseconds(20))
        // Read twice, either side of a suspension: both reads have to see the same invocation's arguments.
        let first = token
        try await Task.sleep(for: .milliseconds(20))
        return "\(first)|\(token)|\(note ?? "-")"
    }
}


/// Reads its parameter from a child task, to pin that the arguments reach structured children too.
private struct ChildTaskEchoFunction: LLMTool {
    let name = "echo_from_child"
    let description = "Echoes the token it is given, from a child task"

    @Parameter(description: "The token to echo back")
    var token: String

    func execute() async throws -> String? {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                try? await Task.sleep(for: .milliseconds(10))
                return token
            }
            return await group.reduce(into: "") { $0 += $1 }
        }
    }
}


/// Records how many invocations were running at once, so concurrency can be asserted rather than timed.
private final class ConcurrencyWitness: Sendable {
    private let state = Mutex<(inFlight: Int, peak: Int)>((inFlight: 0, peak: 0))

    /// The most invocations that were ever in flight together.
    var peak: Int {
        state.withLock { $0.peak }
    }

    func enter() {
        state.withLock { state in
            state.inFlight += 1
            state.peak = max(state.peak, state.inFlight)
        }
    }

    func leave() {
        state.withLock { $0.inFlight -= 1 }
    }
}


/// A function without parameters, which shares nothing at all.
private struct ParameterlessFunction: LLMTool {
    let name = "no_arguments"
    let description = "Takes nothing"

    let witness: ConcurrencyWitness

    func execute() async throws -> String? {
        witness.enter()
        defer { witness.leave() }
        try await Task.sleep(for: .milliseconds(40))
        return "done"
    }
}


/// Echoes its argument while recording how many invocations overlapped.
private struct WitnessedFunction: LLMTool {
    let name = "witnessed_echo"
    let description = "Echoes the token it is given"

    let witness: ConcurrencyWitness

    @Parameter(description: "The token to echo back")
    var token: String

    init(witness: ConcurrencyWitness) {
        self.witness = witness
    }

    func execute() async throws -> String? {
        witness.enter()
        defer { witness.leave() }
        try await Task.sleep(for: .milliseconds(40))
        return token
    }
}


/// Covers concurrent invocation of one ``LLMTool``.
///
/// A model decides how many calls to issue, and parallel tool calls mean several can target the same function in a
/// single turn. Those calls share one registered instance, so the arguments have to belong to the invocation rather
/// than to the function — and, just as importantly, the calls have to actually run at the same time.
@Suite("LLM Function Concurrency")
struct LLMFunctionConcurrencyTests {
    /// Runs `count` invocations of one function at once, returning what each sent and what it got back.
    private func echoConcurrently(
        _ function: SlowEchoFunction,
        count: Int
    ) async throws -> [(sent: String, received: String)] {
        try await withThrowingTaskGroup(of: (sent: String, received: String).self) { group in
            for index in 0..<count {
                group.addTask {
                    let token = "token-\(index)"
                    let payload = Data(#"{"token":"\#(token)","note":"note-\#(index)"}"#.utf8)
                    let arguments = try function.arguments(from: payload)
                    let received = try await function.execute(with: arguments) ?? ""
                    return (sent: "\(token)|\(token)|note-\(index)", received: received)
                }
            }
            return try await group.reduce(into: [(sent: String, received: String)]()) { $0.append($1) }
        }
    }

    @Test("Concurrent calls to one function each execute with their own arguments")
    func concurrentCallsKeepTheirArguments() async throws {
        let results = try await echoConcurrently(SlowEchoFunction(), count: 16)

        for result in results {
            #expect(result.sent == result.received, "a call executed with another call's arguments")
        }
        #expect(Set(results.map(\.received)).count == results.count, "every argument should come back exactly once")
    }

    @Test("A hundred concurrent calls to one function all keep their arguments")
    func survivesHeavyConcurrency() async throws {
        let results = try await echoConcurrently(SlowEchoFunction(), count: 100)

        #expect(results.count == 100, "no invocation may be lost")
        let crossed = results.filter { $0.sent != $0.received }
        #expect(crossed.isEmpty, "\(crossed.count) of 100 calls executed with another call's arguments")
    }

    @Test("Concurrent calls to one function are not serialized")
    func concurrentCallsRunInParallel() async throws {
        // Counting what overlapped answers the question directly. A wall-clock budget would only say the machine
        // was fast enough, and would fail on a busy runner without anything having regressed.
        let witness = ConcurrencyWitness()
        let function = WitnessedFunction(witness: witness)
        let count = 20

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    let arguments = try function.arguments(from: Data(#"{"token":"t-\#(index)"}"#.utf8))
                    _ = try await function.execute(with: arguments)
                }
            }
            try await group.waitForAll()
        }

        #expect(witness.peak > 1, "calls to one function must overlap; a serializing implementation peaks at 1")
    }

    @Test("The arguments reach a child task the function spawns")
    func argumentsReachChildTasks() async throws {
        let function = ChildTaskEchoFunction()
        let results = try await withThrowingTaskGroup(of: (sent: String, received: String).self) { group in
            for index in 0..<8 {
                group.addTask {
                    let token = "child-\(index)"
                    let arguments = try function.arguments(from: Data(#"{"token":"\#(token)"}"#.utf8))
                    return (sent: token, received: try await function.execute(with: arguments) ?? "")
                }
            }
            return try await group.reduce(into: [(sent: String, received: String)]()) { $0.append($1) }
        }

        for result in results {
            #expect(result.sent == result.received, "a child task read another invocation's arguments")
        }
    }

    @Test("An omitted optional argument does not inherit the previous call's value")
    func omittedArgumentsDoNotLeakBetweenCalls() async throws {
        let function = SlowEchoFunction()

        let withNote = try function.arguments(from: Data(#"{"token":"a","note":"remembered"}"#.utf8))
        _ = try await function.execute(with: withNote)

        let withoutNote = try function.arguments(from: Data(#"{"token":"b"}"#.utf8))
        let second = try await function.execute(with: withoutNote)

        #expect(second == "b|b|-", "the omitted note should be absent, not inherited; got: \(second ?? "nil")")
    }

    @Test("Parameterless functions run concurrently too")
    func parameterlessFunctionsRunConcurrently() async throws {
        let witness = ConcurrencyWitness()
        let function = ParameterlessFunction(witness: witness)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let arguments = try function.arguments(from: Data("{}".utf8))
                    _ = try await function.execute(with: arguments)
                }
            }
            try await group.waitForAll()
        }
        #expect(witness.peak > 1, "a function with nothing to share must never queue")
    }
}
