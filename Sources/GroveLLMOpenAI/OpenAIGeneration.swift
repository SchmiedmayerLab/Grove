//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
final class OpenAIGeneration: Sendable {
    private struct State: Sendable {
        var finished = false
        var task: Task<Void, Never>?
        var request = 0
        var attempt = 0
        var active: LLMRequestResult?
        var lastStatus: LLMGenerationStatus?
        var lastReason: LLMFinishReason?
        var attempts = 0
        var total = LLMTokenUsage(inputTokens: 0, outputTokens: 0)

        private static func sum(_ subtotal: Int?, _ reported: Int?) -> Int? {
            guard let subtotal, let reported, reported >= 0 else {
                return nil
            }
            let sum = subtotal.addingReportingOverflow(reported)
            return sum.overflow ? nil : sum.partialValue
        }

        mutating func close(_ status: LLMGenerationStatus) -> LLMRequestResult? {
            guard var result = active else {
                return nil
            }
            active = nil
            result.status = status
            lastStatus = status
            lastReason = result.reason
            attempts += 1
            total.inputTokens = Self.sum(total.inputTokens, result.usage.inputTokens)
            total.outputTokens = Self.sum(total.outputTokens, result.usage.outputTokens)
            return result
        }
    }

    private let state = Mutex(State())
    private let send: @Sendable (LLMGenerationEvent) -> Bool
    private let terminate: @Sendable ((any Error)?) -> Void

    var isCancelled: Bool { state.withLock { $0.finished } || Task.isCancelled }

    init(send: @escaping @Sendable (LLMGenerationEvent) -> Bool, terminate: @escaping @Sendable ((any Error)?) -> Void) {
        self.send = send
        self.terminate = terminate
    }

    static func stream<Value: Sendable>(
        capacity: Int = 256,
        selecting select: @escaping @Sendable (LLMGenerationEvent) -> Value?
    ) -> (OpenAIGeneration, AsyncThrowingStream<Value, any Error>) {
        let (stream, continuation) = AsyncThrowingStream<Value, any Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        let invocation = OpenAIGeneration(send: { event in
            guard let value = select(event) else {
                return true
            }
            if case .enqueued = continuation.yield(value) {
                return true
            }
            return false
        }, terminate: { continuation.finish(throwing: $0) })
        continuation.onTermination = { [weak invocation] reason in
            if case .cancelled = reason { invocation?.finish(throwing: CancellationError()) }
        }
        return (invocation, stream)
    }

    func attach(_ task: Task<Void, Never>) {
        let stopped = state.withLock { state in
            if !state.finished { state.task = task }
            return state.finished
        }
        if stopped { task.cancel() }
    }

    nonisolated(nonsending) func observingAttempts<Result>(
        _ operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result {
        try await RetryMiddleware.$onAttempt.withValue({ event in
            switch event {
            case .dispatch: self.dispatch()
            case .failed: self.endRequest(.failed)
            case .cancelled: self.endRequest(.cancelled)
            }
        }, operation: operation)
    }

    func beginRequest() {
        state.withLock { state in
            state.lastStatus = nil
            state.lastReason = nil
            state.request += 1
            state.attempt = 0
        }
    }

    func dispatch() {
        // A middleware may reject an otherwise successful HTTP response and retry it.
        endRequest(.failed)
        state.withLock { state in
            guard !state.finished else {
                return
            }
            state.attempt += 1
            state.active = .init(request: state.request, attempt: state.attempt, status: .failed)
        }
    }

    func observe(id: String?, model: String?, input: Int?, output: Int?, reason: LLMFinishReason? = nil) {
        state.withLock { state in
            if let id, !id.isEmpty { state.active?.providerID = id }
            if let model, !model.isEmpty { state.active?.model = model }
            if let input, input >= 0 { state.active?.usage.inputTokens = input }
            if let output, output >= 0 { state.active?.usage.outputTokens = output }
            if let reason { state.active?.reason = reason }
        }
    }

    func text(_ text: String) {
        let overflow = state.withLock { state in
            !state.finished && !Task.isCancelled && !send(.textDelta(text))
        }
        if overflow { finish(throwing: LLMGenerationStreamError.bufferOverflow) }
    }

    func endRequest(_ status: LLMGenerationStatus) {
        let overflow = state.withLock { state in
            guard !state.finished else {
                return false
            }
            state.lastStatus = status
            guard let result = state.close(status) else {
                return false
            }
            return !send(.requestFinished(result))
        }
        if overflow { finish(throwing: LLMGenerationStreamError.bufferOverflow) }
    }

    func finish(throwing error: (any Error)? = nil) {
        let outcome = state.withLock { state -> (task: Task<Void, Never>?, error: (any Error)?)? in
            guard !state.finished else {
                return nil
            }
            state.finished = true
            let status: LLMGenerationStatus
            if error is CancellationError || Task.isCancelled {
                status = .cancelled
            } else if error != nil {
                status = .failed
            } else if state.active != nil || state.lastReason == .toolCalls {
                // An open request or unanswered tool calls mean the generation stopped before its answer.
                status = .failed
            } else {
                status = state.lastStatus ?? .failed
            }
            let task = state.task
            state.task = nil
            var delivered = true
            if let request = state.close(status) { delivered = send(.requestFinished(request)) }
            let usage = state.attempts == 0 ? LLMTokenUsage() : state.total
            delivered = send(.finished(.init(status: status, attempts: state.attempts, usage: usage))) && delivered
            let terminalError: (any Error)?
            switch status {
            case .cancelled: terminalError = CancellationError()
            case .failed: terminalError = error ?? LLMOpenAIError.generationError
            case .completed, .incomplete: terminalError = nil
            }
            return (task, delivered ? terminalError : LLMGenerationStreamError.bufferOverflow)
        }
        guard let outcome else {
            return
        }
        if outcome.error != nil { outcome.task?.cancel() }
        terminate(outcome.error)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OpenAIGeneration {
    static func reason(_ providerReason: String) -> LLMFinishReason {
        switch providerReason {
        case "stop": .stop
        case "length", "max_output_tokens": .outputLimit
        case "content_filter": .contentFilter
        case "tool_calls", "function_call": .toolCalls
        default: .other
        }
    }

    /// A Responses terminal event supplies its status in the event name, an unstreamed response in the body.
    static func responseStatus(_ reported: String?, expected: String? = nil) throws -> LLMGenerationStatus {
        if let reported, let expected, reported != expected {
            throw LLMOpenAIError.generationError
        }
        switch reported ?? expected {
        case "completed": return .completed
        case "incomplete": return .incomplete
        case "cancelled": throw CancellationError()
        default: throw LLMOpenAIError.generationError
        }
    }

    func endResponse(_ status: LLMGenerationStatus, hasTools: Bool) {
        if status == .completed, hasTools {
            observe(id: nil, model: nil, input: nil, output: nil, reason: .toolCalls)
        }
        endRequest(status)
    }

    /// Reads the identity, usage and incomplete reason of the response a Responses stream event carries.
    /// Fields of an unexpected type stay unknown.
    func observe(responseEvent json: Data) {
        guard let metadata = (try? JSONDecoder().decode(ResponseEvent.self, from: json))?.response else {
            return
        }
        observe(
            id: metadata.id,
            model: metadata.model,
            input: metadata.usage?.inputTokens,
            output: metadata.usage?.outputTokens,
            reason: metadata.incompleteReason.map(Self.reason)
        )
    }
}
