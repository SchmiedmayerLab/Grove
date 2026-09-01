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


/// A long-running backgrund exporting task that fetches and processes HealthKit data.
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
    
    @MainActor private var descriptor: ExportSessionDescriptor {
        didSet {
            persistDescriptor(descriptor)
        }
    }
    
    /// The `Task` on which the session's exporting is executed.
    @ObservationIgnored @MainActor private var task: Task<Void, Never>?
    
    @MainActor private(set) var state: BulkExportSessionState = .paused {
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
        batchProcessor: Processor
    ) async throws {
        self.sessionId = sessionId
        self.bulkExporter = bulkExporter
        self.healthKit = healthKit
        self.batchProcessor = batchProcessor
        let storageKey = LocalStorageKey<ExportSessionDescriptor>(BulkHealthExporter.localStorageKey(forSessionId: sessionId))
        self.persistDescriptor = .init(localStorage: localStorage, storageKey: storageKey)
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
        guard task == nil || task?.isCancelled == true else {
            // is already running
            throw .alreadyRunning
        }
        state = .running
        let (batchResults, batchResultsContinuation) = AsyncStream.makeStream(of: Processor.Output.self)
        if retryFailedBatches {
            self.descriptor.unmarkAllFailedBatches()
        }
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
        guard let task else {
            return
        }
        switch state {
        case .paused, .completed, .terminated:
            return
        case .running:
            pendingStateChangeRequest = .paused
            task.cancel()
            _ = await task.result
            await persistDescriptor.flush()
        }
    }
    
    
    @MainActor
    func _terminate() async { // swiftlint:disable:this identifier_name
        defer {
            bulkExporter.remove(self)
        }
        guard let task else {
            state = .terminated
            await persistDescriptor.flush()
            return
        }
        switch state {
        case .terminated, .completed:
            break
        case .paused:
            state = .terminated
        case .running:
            pendingStateChangeRequest = .terminated
            task.cancel()
            _ = await task.result
        }
        await persistDescriptor.flush()
    }


    @MainActor
    private func record(_ batch: ExportBatch, result: Result<Void, any Error>) -> Task<Void, any Error> {
        descriptor.record(batch, result: result)
        return persistDescriptor.checkpoint()
    }


    @MainActor
    private func markPersistenceFailure(for batch: ExportBatch, error: any Error) -> Task<Void, any Error> {
        descriptor.markPersistenceFailure(for: batch, error: error)
        return persistDescriptor.checkpoint()
    }


    @concurrent
    private func publish(
        _ result: Processor.Output,
        for batch: ExportBatch,
        to continuation: AsyncStream<Processor.Output>.Continuation
    ) async {
        let persistence = await record(batch, result: .success(()))
        do {
            try await persistence.value
        } catch {
            bulkExporter.logger.error(
                "Processed batch \(String(describing: batch)), but failed to persist its completion: \(String(describing: error)). Will schedule it for retry."
            )
            let rollbackPersistence = await markPersistenceFailure(for: batch, error: error)
            _ = await rollbackPersistence.result
            return
        }
        continuation.yield(result)
        await batchProcessor.didPersist(result)
    }
    
    
    @concurrent
    private func _run( // swiftlint:disable:this function_body_length cyclomatic_complexity
        concurrencyLevel: BulkExportConcurrencyLevel,
        batchResultsContinuation: AsyncStream<Processor.Output>.Continuation
    ) async {
        let logger = self.bulkExporter.logger
        
        /// processes a single batch
        ///
        /// - invariant: the batch must not have been processed already. (i.e., `batch.result == nil` must be true.)
        let handleBatch = { @Sendable (batch: ExportBatch) in
            switch batch.result {
            case .success, .failure:
                // unreachable (taken care of by caller)
                return
            case nil: // the batch hasn't run yet
                await MainActor.run {
                    _ = self.currentBatches.insert(batch)
                }
                defer {
                    Task { @MainActor in
                        self.currentBatches.remove(batch)
                    }
                }
                let result: Processor.Output
                do {
                    result = try await self.queryAndProcess(sampleType: batch.sampleType, for: batch.timeRange)
                } catch let error as QueryAndProcessError {
                    if !(error.underlyingError is CancellationError && Task.isCancelled) {
                        logger.error(
                            "Failed to query and process batch \(String(describing: batch)): \(String(describing: error)). Will schedule for retry on next app launch."
                        )
                    }
                    let persistence = await self.record(batch, result: .failure(error.underlyingError))
                    _ = await persistence.result
                    return
                } catch {
                    // SAFETY: this is in fact unreachable: the `queryAndProcess` call above has a typed throw, but the compiler doesn't seem to understand this.
                    fatalError("unreachable")
                }
                await self.publish(result, for: batch, to: batchResultsContinuation)
            }
        }
        
        let isDone = { @MainActor @Sendable in
            switch self.pendingStateChangeRequest {
            case .paused:
                self.state = .paused
            case .terminated:
                self.state = .terminated
            case nil:
                if !(self.state == .paused || self.state == .terminated) {
                    self.state = .completed
                }
            }
            self.pendingStateChangeRequest = nil
            self.task = nil
            batchResultsContinuation.finish()
        }
        
        await withManagedTaskQueue(limit: concurrencyLevel.effectiveLimit) { taskQueue in
            let batches = await self.descriptor.pendingBatches
            for batch in batches where batch.result == nil {
                taskQueue.addTask {
                    guard !Task.isCancelled else {
                        return
                    }
                    await handleBatch(batch)
                }
            }
        }
        await isDone()
    }
}


// MARK: Helpers

@available(iOS 18, macOS 15, watchOS 11, *)
/* private-but-tests */ final class SessionDescriptorPersisting: Sendable {
    @globalActor
    private actor PersistSessionStateActor {
        static let shared = PersistSessionStateActor()
    }
    
    private let storeDescriptor: @Sendable (ExportSessionDescriptor) throws -> Void
    private let persistTask = Mutex<Task<Void, any Error>?>(nil)
    
    init(localStorage: LocalStorage, storageKey: LocalStorageKey<ExportSessionDescriptor>) {
        self.storeDescriptor = { descriptor in
            try localStorage.store(descriptor, for: storageKey)
        }
    }

    init(storeDescriptor: @escaping @Sendable (ExportSessionDescriptor) throws -> Void) {
        self.storeDescriptor = storeDescriptor
    }
    
    @discardableResult
    func callAsFunction(_ descriptor: ExportSessionDescriptor) -> Task<Void, any Error> {
        persistTask.withLock { persistTask in
            let previousTask = persistTask
            let nextTask = Task { @PersistSessionStateActor in
                if let previousTask {
                    _ = try? await previousTask.value
                }
                try storeDescriptor(descriptor)
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

    func flush() async {
        let task = persistTask.withLock { $0 }
        if let task {
            _ = await task.result
        }
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
            samples = try await healthKit.query(sampleType, timeRange: .init(timeRange))
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
