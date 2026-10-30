//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// swiftlint:disable file_types_order

import Foundation
import GroveFoundation
import GroveHealthKit
import GroveLocalStorage
import HealthKit
import Synchronization


/// A long-running background exporting task that fetches and processes HealthKit data.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
final class BulkExportSessionImpl<Processor: BatchProcessor>: Sendable, BulkExportSession {
    typealias Processor = Processor
    
    private enum StateChangeRequest {
        case paused, terminated
    }
    
    let sessionId: BulkExportSessionIdentifier
    private unowned let bulkExporter: BulkHealthExporter
    private unowned let healthKit: HealthKit
    @ObservationIgnored private let batchProcessor: Processor
    @ObservationIgnored @MainActor private var pendingStateChangeRequest: StateChangeRequest?
    @ObservationIgnored private let persistDescriptor: SessionDescriptorPersisting
    @ObservationIgnored private let processBatch: (@Sendable (ExportBatch) async throws -> Processor.Output)?
    // Successful processing is retained across checkpoint failures in this live session.
    @ObservationIgnored @MainActor private var unpublishedOutputs: [ExportBatch: Processor.Output] = [:]
    @ObservationIgnored @MainActor private var checkpointFailure: CheckpointWriteFailure?
    
    @MainActor private var descriptor: ExportSessionDescriptor {
        didSet {
            persistDescriptor(descriptor)
        }
    }
    
    /// The `Task` on which the session's exporting is executed.
    @ObservationIgnored @MainActor private var task: Task<Void, Never>?
    
    @MainActor private(set) var state: BulkExportSessionState = .paused(reason: .notStarted) {
        willSet {
            if state == .terminated && newValue != .terminated {
                preconditionFailure("Attempted to move already-terminated session back into non-terminated state")
            }
        }
    }
    
    @MainActor var pendingBatches: [ExportBatch] {
        descriptor.pendingBatches.filter { $0.result?.isFailure != true }
    }
    @MainActor var completedBatches: [ExportBatch] {
        descriptor.completedBatches
    }
    @MainActor var failedBatches: [ExportBatch] {
        descriptor.pendingBatches.filter { $0.result?.isFailure == true }
    }
    @MainActor var numTotalBatches: Int {
        descriptor.pendingBatches.count + descriptor.completedBatches.count
    }
    @MainActor private(set) var currentBatches = Set<ExportBatch>()
    
    @MainActor var progress: BulkExportSessionProgress? {
        guard state == .running else {
            return nil
        }
        return BulkExportSessionProgress(
            numCompletedBatches: completedBatches.count,
            numFailedBatches: failedBatches.count,
            numTotalBatches: numTotalBatches,
            activeBatches: currentBatches
        )
    }
    
    @MainActor
    internal init(
        sessionId: BulkExportSessionIdentifier,
        bulkExporter: BulkHealthExporter,
        healthKit: HealthKit,
        sampleTypes: SampleTypesCollection,
        startDate: ExportSessionStartDate,
        endDate: Date,
        batchSize: ExportSessionBatchSize,
        localStorage: LocalStorage,
        batchProcessor: Processor,
        persistence: SessionDescriptorPersisting? = nil,
        processBatch: (@Sendable (ExportBatch) async throws -> Processor.Output)? = nil
    ) async throws {
        self.sessionId = sessionId
        self.bulkExporter = bulkExporter
        self.healthKit = healthKit
        self.batchProcessor = batchProcessor
        self.processBatch = processBatch
        let storageKey = LocalStorageKey<ExportSessionDescriptor>(
            BulkHealthExporter.localStorageKey(forSessionId: sessionId),
            setting: bulkExporter.checkpointStorageSetting
        )
        self.persistDescriptor = persistence ?? .init(localStorage: localStorage, storageKey: storageKey)
        if let descriptor = try localStorage.load(storageKey) {
            self.descriptor = descriptor
            // when restoring a previously-persisted session, we want to "reset" all failed batches, so that everything is processed again.
            // this is fine, because we only end up in here (in the ExportSession init) once per session per app lifecycle.
            // (once the session has been created, any further calls to BulkExporter.session() will return the previously-created Session.)
            for idx in self.descriptor.pendingBatches.indices {
                switch self.descriptor.pendingBatches[idx].result {
                case nil, .success:
                    break
                case .failure:
                    self.descriptor.pendingBatches[idx].result = nil
                }
            }
        } else {
            // if there's no persisted state for this session identifier, we create a new descriptor,
            // which will operate on all samples created up until right now.
            var descriptor = ExportSessionDescriptor(
                sessionId: sessionId,
                startDate: startDate,
                endDate: endDate,
            )
            for sampleType in sampleTypes {
                await descriptor.add(sampleType: sampleType, batchSize: batchSize, healthKit: healthKit)
            }
            self.descriptor = descriptor
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BulkExportSessionImpl {
    @MainActor
    func start(retryFailedBatches: Bool, concurrencyLevel: BulkExportConcurrencyLevel) throws(StartSessionError) -> AsyncStream<Processor.Output> {
        switch state {
        case .running:
            throw .alreadyRunning
        case .completed, .paused:
            break
        case .terminated:
            throw .isTerminated
        }
        guard task == nil else {
            throw .alreadyRunning
        }
        state = .running
        checkpointFailure = nil
        let (batchResults, batchResultsContinuation) = AsyncStream.makeStream(of: Processor.Output.self)
        if retryFailedBatches {
            descriptor.unmarkAllFailedBatches()
        }
        persistDescriptor(descriptor)
        task = Task.detached {
            await self._run(
                concurrencyLevel: concurrencyLevel,
                batchResultsContinuation: batchResultsContinuation
            )
        }
        return batchResults
    }

    @MainActor
    func pause() async {
        guard let task, state == .running else {
            return
        }
        if pendingStateChangeRequest != .terminated {
            pendingStateChangeRequest = .paused
        }
        task.cancel()
        _ = await task.result
    }

    @MainActor
    func _terminate() async { // swiftlint:disable:this identifier_name
        defer {
            bulkExporter.remove(self)
        }
        if let task {
            pendingStateChangeRequest = .terminated
            task.cancel()
            _ = await task.result
        }
        state = .terminated
        unpublishedOutputs.removeAll()
        // A scheduled descriptor write must not recreate restoration info after deletion.
        _ = await flushDescriptor()
    }

    @MainActor
    private func beginBatch(_ batch: ExportBatch) -> Bool {
        // The task queue eagerly enqueues work. Check here, when a worker actually starts.
        guard !Task.isCancelled, pendingStateChangeRequest == nil, checkpointFailure == nil else {
            return false
        }
        currentBatches.insert(batch)
        return true
    }

    @MainActor
    private func record(
        _ batch: ExportBatch,
        result: Result<Processor.Output, any Error>
    ) -> Task<Void, any Error> {
        // The original batch's result is part of its hash. Remove it before changing the descriptor.
        currentBatches.remove(batch)
        if case .success(let output) = result {
            unpublishedOutputs[batch] = output
        }
        descriptor.finishBatch(
            batch,
            result: result.map { _ in () },
            cancellationWasRequested: pendingStateChangeRequest != nil
        )
        return persistDescriptor.checkpoint()
    }

    @MainActor
    private func noteCheckpointFailure(_ error: any Error) {
        // Keep the first failure even if a later snapshot succeeds: it may already have stopped workers.
        if checkpointFailure == nil {
            checkpointFailure = CheckpointWriteFailure(error)
            bulkExporter.logger.error("Failed to persist export checkpoint: \(String(describing: error))")
        }
    }

    @MainActor
    private func publishOutput(for batch: ExportBatch, to continuation: AsyncStream<Processor.Output>.Continuation) async {
        // Remove before suspending in didPersist, so this output can be acknowledged only once.
        guard let output = unpublishedOutputs.removeValue(forKey: batch) else {
            return
        }
        continuation.yield(output)
        await batchProcessor.didPersist(output)
    }

    @MainActor
    private func flushDescriptor() async -> CheckpointWriteFailure? {
        do {
            try await persistDescriptor.flush()
            return nil
        } catch {
            noteCheckpointFailure(error)
            return CheckpointWriteFailure(error)
        }
    }

    @concurrent
    private func handleBatch(_ batch: ExportBatch, continuation: AsyncStream<Processor.Output>.Continuation) async {
        guard await beginBatch(batch) else {
            return
        }
        let result: Result<Processor.Output, any Error>
        do {
            if let processBatch {
                result = .success(try await processBatch(batch))
            } else {
                result = .success(try await queryAndProcess(sampleType: batch.sampleType, for: batch.timeRange))
            }
        } catch {
            let underlyingError = (error as? QueryAndProcessError)?.underlyingError ?? error
            let cancellationWasRequested = await pendingStateChangeRequest != nil
            if !(underlyingError is CancellationError && cancellationWasRequested) {
                bulkExporter.logger.error("Failed to query and process batch \(String(describing: batch)): \(String(describing: underlyingError))")
            }
            result = .failure(underlyingError)
        }
        let checkpoint = await record(batch, result: result)
        do {
            try await checkpoint.value
            await publishOutput(for: batch, to: continuation)
        } catch {
            // Do not roll back successful processing. Resume retries this checkpoint and held output.
            await noteCheckpointFailure(error)
        }
    }

    @concurrent
    private func _run(
        concurrencyLevel: BulkExportConcurrencyLevel,
        batchResultsContinuation: AsyncStream<Processor.Output>.Continuation
    ) async {
        // Persist the current descriptor before publishing held outputs or processing more batches.
        // This also retries a failed checkpoint when no batches need processing anymore.
        if await flushDescriptor() == nil {
            let heldBatches = await Array(unpublishedOutputs.keys)
            for batch in heldBatches {
                await publishOutput(for: batch, to: batchResultsContinuation)
            }
            await withManagedTaskQueue(limit: concurrencyLevel.effectiveLimit) { taskQueue in
                let batches = await self.descriptor.pendingBatches
                for batch in batches where batch.result == nil {
                    taskQueue.addTask {
                        await self.handleBatch(batch, continuation: batchResultsContinuation)
                    }
                }
            }
        }
        // Drain child tasks and all queued writes before finishing the stream. A transient write
        // failure still pauses this run; failed publications are retried on the next explicit start.
        _ = await flushDescriptor()
        await finishRun(continuation: batchResultsContinuation)
    }

    @MainActor
    private func finishRun(continuation: AsyncStream<Processor.Output>.Continuation) {
        task = nil
        currentBatches.removeAll()
        switch pendingStateChangeRequest {
        case .terminated:
            state = .terminated
            unpublishedOutputs.removeAll()
        case .paused, nil:
            if let checkpointFailure {
                state = .paused(reason: .failure(.checkpointWriteFailed(checkpointFailure)))
            } else if pendingStateChangeRequest == .paused {
                state = .paused(reason: .requested)
            } else if !descriptor.pendingBatches.isEmpty {
                state = .paused(reason: .failedBatches)
            } else {
                state = .completed
            }
        }
        pendingStateChangeRequest = nil
        continuation.finish()
    }
}


// MARK: Helpers

@available(iOS 18, macOS 15, watchOS 11, *)
final class SessionDescriptorPersisting: Sendable {
    @globalActor
    actor PersistSessionStateActor {
        static let shared = PersistSessionStateActor()
    }

    private let store: @Sendable (ExportSessionDescriptor) throws -> Void
    private let persistTask = Mutex<Task<Void, any Error>?>(nil)

    init(localStorage: LocalStorage, storageKey: LocalStorageKey<ExportSessionDescriptor>) {
        self.store = { try localStorage.store($0, for: storageKey) }
    }

    init(store: @escaping @Sendable (ExportSessionDescriptor) throws -> Void) {
        self.store = store
    }

    /// Registers and writes every snapshot in mutation order. Each task acknowledges its own write.
    @discardableResult
    func callAsFunction(_ descriptor: ExportSessionDescriptor) -> Task<Void, any Error> {
        // Registration is synchronous so an older snapshot cannot be enqueued after a newer one.
        persistTask.withLock { persistTask in
            let previousTask = persistTask
            let nextTask = Task { @PersistSessionStateActor in
                if let previousTask {
                    _ = await previousTask.result
                }
                // Keep the write synchronous on this actor to preserve replacement order.
                try store(descriptor)
            }
            persistTask = nextTask
            return nextTask
        }
    }

    func checkpoint() -> Task<Void, any Error> {
        persistTask.withLock { persistTask in
            guard let persistTask else {
                preconditionFailure("A descriptor mutation did not schedule persistence")
            }
            return persistTask
        }
    }

    /// Waits for the latest registered snapshot; call after producers have stopped.
    func flush() async throws {
        let task = persistTask.withLock { $0 }
        try await task?.value
    }
}


private enum QueryAndProcessError: Error, Sendable {
    case query(any Error)
    case process(any Error)
    
    var underlyingError: any Error {
        switch self {
        case .query(let error), .process(let error):
            error
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BulkExportSessionImpl {
    nonisolated private func queryAndProcess<Sample: _HKSampleWithSampleType>(
        sampleType: some AnySampleType<Sample>,
        for timeRange: Range<Date>
    ) async throws(QueryAndProcessError) -> Processor.Output {
        let sampleType = SampleType(sampleType)
        let samples: [Sample]
        do {
            samples = try await healthKit.query(
                sampleType,
                timeRange: .ever,
                predicate: ExportBatch.samplePredicate(for: timeRange)
            )
        } catch {
            throw .query(error)
        }
        do {
            return try await batchProcessor.process(samples, of: sampleType)
        } catch {
            throw .process(error)
        }
    }
}


extension BulkExportConcurrencyLevel {
    fileprivate var effectiveLimit: Int {
        switch self {
        case .disabled:
            1
        case .limit(let limit):
            limit
        case .unlimited:
            .max
        }
    }
}

#endif
