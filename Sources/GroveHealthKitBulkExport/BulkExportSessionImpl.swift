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
            if state != .terminated {
                persistDescriptor(descriptor)
            }
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
    
    @MainActor private(set) var persistenceError: (any Error)?

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
        persistence: SessionDescriptorPersisting? = nil
    ) async throws {
        self.sessionId = sessionId
        self.bulkExporter = bulkExporter
        self.healthKit = healthKit
        self.batchProcessor = batchProcessor
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
        guard task == nil || task?.isCancelled == true else {
            // is already running
            throw .alreadyRunning
        }
        persistenceError = nil
        state = .running
        let (batchResults, batchResultsContinuation) = AsyncStream.makeStream(of: Processor.Output.self)
        if retryFailedBatches {
            self.descriptor.unmarkAllFailedBatches()
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
        }
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
        // A scheduled descriptor write must not recreate restoration info after deletion.
        await flushDescriptor()
    }
    
    
    @MainActor
    private func flushDescriptor() async {
        do {
            try await persistDescriptor.flush()
            persistenceError = nil
        } catch {
            persistenceError = error
            bulkExporter.logger.error("Failed to persist export checkpoint: \(String(describing: error))")
        }
    }

    @concurrent
    private func _run( // swiftlint:disable:this function_body_length
        concurrencyLevel: BulkExportConcurrencyLevel,
        batchResultsContinuation: AsyncStream<Processor.Output>.Continuation
    ) async {
        let logger = self.bulkExporter.logger
        let popBatch = { @MainActor @Sendable (batch: ExportBatch, result: Result<Void, any Error>) in
            // Remove the original batch synchronously; its result is part of its hash.
            defer { self.currentBatches.remove(batch) }
            self.descriptor.finishBatch(batch, result: result)
        }
        
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
                let result: Processor.Output
                do {
                    result = try await self.queryAndProcess(sampleType: batch.sampleType, for: batch.timeRange)
                } catch let error as QueryAndProcessError {
                    if !(error.underlyingError is CancellationError && Task.isCancelled) {
                        logger.error(
                            "Failed to query and process batch \(String(describing: batch)): \(String(describing: error)). Will schedule for retry on next app launch."
                        )
                    }
                    await popBatch(batch, .failure(error.underlyingError))
                    return
                } catch {
                    // SAFETY: this is in fact unreachable: the `queryAndProcess` call above has a typed throw, but the compiler doesn't seem to understand this.
                    fatalError("unreachable")
                }
                batchResultsContinuation.yield(result)
                await popBatch(batch, .success(()))
            }
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
        // Drain child tasks before finishing the stream.
        await flushDescriptor()
        await MainActor.run {
            self.task = nil
            self.currentBatches.removeAll()
            switch self.pendingStateChangeRequest {
            case .terminated:
                self.state = .terminated
            case .paused:
                self.state = .paused
            case nil:
                self.state = self.descriptor.pendingBatches.isEmpty && self.persistenceError == nil ? .completed : .paused
            }
            self.pendingStateChangeRequest = nil
            batchResultsContinuation.finish()
        }
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

    /// Registers snapshots in mutation order, then writes asynchronously.
    func callAsFunction(_ descriptor: ExportSessionDescriptor) {
        // An outer Task could reorder registrations and let an older snapshot replace a newer one.
        persistTask.withLock { persistTask in
            persistTask?.cancel()
            persistTask = Task { @PersistSessionStateActor in
                guard !Task.isCancelled else {
                    return
                }
                // Keep the write synchronous on this actor to preserve replacement order.
                try store(descriptor)
            }
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
