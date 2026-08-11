//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A Managed Task Queue
///
/// Your code does not use this type directly; instead it is used by ``withManagedTaskQueue(limit:_:)`` and allows you to add child tasks.
public struct ManagedTaskQueue: ~Copyable {
    @usableFromInline typealias Operation = @Sendable () async -> Void
    
    @usableFromInline let continuation: AsyncStream<Operation>.Continuation
    
    fileprivate init(_ continuation: AsyncStream<Operation>.Continuation) {
        self.continuation = continuation
    }
    
    /// Submits an operation to be executed by the Managed Task Queue.
    @inlinable
    public func addTask(_ operation: @escaping @Sendable () async -> Void) {
        continuation.yield(operation)
    }
}


/// Runs a dynamic number of child tasks, with a maximum concurrency limit.
///
/// The function will return once all child tasks scheduled via ``ManagedTaskQueue/addTask(_:)`` have completed.
///
/// ```swift
/// // Fetches and uploads data, in a way that at most 4 sensors are processed at a time.
/// func uploadNewData(for sensors: [Sensor]) async {
///     await withManagedTaskQueue(limit: 4) { taskQueue in
///         for sensor in sensors {
///             taskQueue.addTask {
///                 let data = await sensor.fetch()
///                 await upload(data)
///             }
///         }
///     }
/// }
/// ```
///
/// - parameter limit: The maximum number of child tasks that are allowed to run at the same time.
/// - parameter body: Will be called with a ``ManagedTaskQueue`` that is used for registering tasks.
///
/// ## Topics
/// ### Classes
/// - ``ManagedTaskQueue``
public func withManagedTaskQueue(limit: Int, _ body: sending @escaping (_ taskQueue: borrowing ManagedTaskQueue) async -> Void) async {
    /// Used to differentiate between the 2 kinds of tasks we schedule with the underlying `TaskGroup`:
    /// - the initial "scheduler" task, which calls `body` to schedule the individual operations with the ``ManagedTaskQueue``
    /// - the worker tasks, which run the operations scheduled on the ``ManagedTaskQueue``.
    enum TaskType {
        case scheduler
        case worker
    }
    let (stream, continuation) = AsyncStream.makeStream(of: ManagedTaskQueue.Operation.self)
    // we need to wrap this as a workaround to be able to mark the `body` parameter as `sending` instead of having to make it `@Sendable`
    let boxedBody = { body }
    await withTaskGroup(of: TaskType.self) { group in
        let body = (consume boxedBody)()
        group.addTask {
            await body(ManagedTaskQueue(continuation))
            continuation.finish()
            return .scheduler
        }
        var activeWorkers = 0 {
            didSet { assert(activeWorkers <= limit) }
        }
        for await operation in stream {
            if activeWorkers >= limit {
                // we're at the limit, and need to wait for a slot to become available.
                // we can't simply call `group.next()` and ignore the result,
                // since the first task will be the initial one that calls `body`.
                loop: while let taskType = await group.next() {
                    switch taskType {
                    case .scheduler:
                        continue
                    case .worker:
                        break loop
                    }
                }
                activeWorkers -= 1
            }
            group.addTask {
                await operation()
                return .worker
            }
            activeWorkers += 1
        }
        // finish all worker tasks before returning from the function
        await group.waitForAll()
    }
}
