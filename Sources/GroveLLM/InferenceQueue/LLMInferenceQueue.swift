//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import Synchronization


/// Queue for scheduling and executing asynchronous LLM inference tasks.
@available(iOS 18, macOS 15, watchOS 11, *)
package final class LLMInferenceQueue<Element>: Sendable {
    package typealias InferenceTask = @Sendable (InferenceResultStream.Continuation) async -> Void
    package typealias InferenceResultStream = AsyncThrowingStream<Element, any Error>

    private final class InferenceQueueElement: Sendable {
        private let pending = Mutex(true)
        private let work: @Sendable () async -> Void
        private let discard: @Sendable () -> Void

        init(work: @escaping @Sendable () async -> Void, discard: @escaping @Sendable () -> Void) {
            self.work = work
            self.discard = discard
        }

        func run() async {
            pending.withLock { $0 = false }
            await work()
        }

        // A cancelled queue can release buffered elements without iterating them.
        deinit {
            if pending.withLock({ $0 }) { discard() }
        }
    }

    /// Errors that can occur during task queue operation.
    package enum QueueError: Error, Sendable {
        /// The queue submission failed
        case submissionFailed

        /// The queue is already running
        case alreadyRunning

        /// The queue was already shut down
        case alreadyShutdown
    }

    /// Represents the current state of the task queue.
    private enum State: Sendable {
        /// Initialized state of the queue, including a buffer of tasks to be processed once the queue is started.
        case initialized(buffer: [InferenceQueueElement])
        /// Processing state of the queue, holding an `AsyncStream` to receive tasks and the matching `Continuation` yielding the tasks into.
        case processing(
            taskStream: AsyncStream<InferenceQueueElement>,
            continuation: AsyncStream<InferenceQueueElement>.Continuation
        )
        /// Shutdown state of the queue.
        case shutdown
    }

    /// The current state of the task queue.
    private let state = Mutex<State>(.initialized(buffer: []))
    /// Maximum number of concurrent tasks
    private let semaphore: AsyncSemaphore
    /// Priority of the dispatched LLM inference tasks in the queue.
    private let taskPriority: TaskPriority?

    private let platformStateStorage = Mutex<LLMPlatformState>(.idle)
    /// The `LLMPlatformState` indicating whether inference jobs are currently being processed.
    package var platformState: LLMPlatformState {
        platformStateStorage.withLock { $0 }
    }

    
    /// Create a queue for processing LLM inference tasks.
    /// - Parameter maxConcurrentTasks: The maximum number of concurrent inference tasks, defaults to no limit.
    /// - Parameter taskPriority: The priority of tasks in the LLM inference queue.
    package init(maxConcurrentTasks: Int = .max, taskPriority: TaskPriority? = nil) {
        self.semaphore = AsyncSemaphore(value: maxConcurrentTasks)
        self.taskPriority = taskPriority
    }


    /// Start the task queue.
    ///
    /// This returns once `shutdown()` has been called and all in-flight tasks have finished or cancelled.
    /// If you need to abruptly stop all work you should cancel the `Task` executing this method.
    ///
    /// The task queue, and by extension this function, can only be run once. If the task queue is already
    /// running or has already been closed then a `LLMInferenceQueue/QueueError` is thrown.
    @available(iOS 18, macOS 15, watchOS 11, *)
    package func runQueue() async throws {
        let stream = try state.withLock { state in
            switch state {
            case .processing:
                throw QueueError.alreadyRunning
            case .shutdown:
                throw QueueError.alreadyShutdown
            case .initialized(let buffer):
                let (stream, continuation) = AsyncStream<InferenceQueueElement>.makeStream(bufferingPolicy: .unbounded)

                state = .processing(
                    taskStream: stream,
                    continuation: continuation
                )

                // Enqueue previously buffered tasks when queue wasn't started yet
                for task in buffer {
                    continuation.yield(task)
                }

                return stream
            }
        }

        defer { shutdown() }
        try await withThrowingDiscardingTaskGroup { group in
            // Start processing `InferenceTask`s as they come in
            for await job in stream {
                try await self.semaphore.waitCheckingCancellation()

                group.addTask(priority: self.taskPriority) {
                    self.platformStateStorage.withLock { platformState in
                        if platformState != .processing {
                            platformState = .processing
                        }
                    }

                    await job.run()

                    if !self.semaphore.signal() {       // indicates if other tasks are waiting
                        self.platformStateStorage.withLock { platformState in
                            platformState = .idle
                        }
                    }
                }
            }

            // Cancel all tasks currently in process when stream/continuation finishes
            group.cancelAll()
        }
    }

    /// Enqueues a unit of work for the LLM inference task queue.
    ///
    /// - Parameters:
    ///   - work: An async-producing LLM inference closure that yields the individual tokens in an `AsyncThrowingStream.
    ///   
    /// - Returns: The `AsyncStream` yielding the generated inference tokens.
    /// - Throws:
    ///   - `QueueError.submissionFailed` if the queue is full or has been terminated.
    ///
    /// After enqueuing, the queue processor will pick up this work and start yielding tokens to the respective `AsyncThrowingStream.
    package func submit(_ work: @escaping InferenceTask) throws -> InferenceResultStream {
        let (stream, continuation) = InferenceResultStream.makeStream(bufferingPolicy: .unbounded)
        try enqueue(discard: { continuation.finish(throwing: CancellationError()) }) { await work(continuation) }
        return stream
    }

    package func enqueue(discard: @escaping @Sendable () -> Void, work: @escaping @Sendable () async -> Void) throws {
        let task = InferenceQueueElement(work: work, discard: discard)

        // Either append to buffer in idle state or obtain continuation in processing state
        let queueContinuation: AsyncStream<InferenceQueueElement>.Continuation? = try state.withLock { state in
            switch state {
            case .processing(_, let continuation):
                return continuation
            case .initialized(var buffer):  // Buffer submitted tasks if queue is not yet processing
                buffer.append(task)
                state = .initialized(buffer: buffer)
                return nil
            case .shutdown:
                throw QueueError.alreadyShutdown
            }
        }

        // If processing has begun, yield immediately
        if let queueContinuation {
            switch queueContinuation.yield(task) {
            case .enqueued:
                break
            case .dropped, .terminated:
                throw QueueError.submissionFailed
            @unknown default:
                fatalError("Unknown yield return case from the continuation of the LLM Inference Task Queue.")
            }
        }
    }

    /// Stops the task queue and prevents any further submissions.
    ///
    /// Calling this method finishes the underlying async stream, which in turn
    /// cancels any in-flight `Task`s. After shutdown, the queue transitions to the
    /// `.shutdown` state and any subsequent `submit(...)` calls will throw.
    ///
    /// - Note: Jobs waiting for the queue to start are discarded.
    package func shutdown() {
        let previous = state.withLock { current in
            let previous = current
            current = .shutdown
            return previous
        }
        if case .processing(_, let continuation) = previous {
            continuation.finish()
        }
    }
}
