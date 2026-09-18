//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveHealthKit
import HealthKit
public import Observation


/// State of a ``BulkExportSession``
public enum BulkExportSessionState: Hashable, Sendable {
    /// The session is currently paused.
    ///
    /// Newly created and restored sessions begin paused with reason `.notStarted`.
    /// Inspect the reason before resuming with `start(retryFailedBatches:concurrencyLevel:)`.
    case paused(reason: BulkExportPauseReason)
    /// The session is currently running.
    case running
    /// All batches succeeded, including empty queries, and the final checkpoint was stored.
    case completed
    /// The session is irrevocably terminated, has been detached from the ``BulkHealthExporter``, and can not be restarted.
    ///
    /// A session enters this state if the ``BulkHealthExporter/deleteSessionRestorationInfo(for:)`` is called for an already-created session.
    case terminated
}


@available(iOS 18, macOS 15, watchOS 11, *)
public struct BulkExportSessionProgress: Hashable, Sendable {
    /// The amount of work that has already been successfully completed, as a value from `0` to `1`.
    public let completion: Double
    /// The number of batches that have been successfully completed.
    public let numCompletedBatches: Int
    /// The number of batches that failed.
    public let numFailedBatches: Int
    /// The total number of batches expected for the session.
    public let numTotalBatches: Int
    /// The export batches that are currently being processed.
    public let activeBatches: Set<ExportBatch>
    
    init(
        numCompletedBatches: Int,
        numFailedBatches: Int,
        numTotalBatches: Int,
        activeBatches: Set<ExportBatch>
    ) {
        self.completion = min(1, Double(numCompletedBatches) / Double(numTotalBatches))
        self.numCompletedBatches = numCompletedBatches
        self.numFailedBatches = numFailedBatches
        self.numTotalBatches = numTotalBatches
        self.activeBatches = activeBatches
    }
}


/// How much concurrency a ``BulkExportSession`` should employ when running.
///
/// Allowing concurrency for a session greatly improves performance, since the session will be able to fetch and process multiple batches at the same time.
public enum BulkExportConcurrencyLevel: Hashable, Sendable {
    /// The session should not process multiple batches at the same time
    case disabled
    /// The session should process at most `limit` batches at the same time.
    case limit(Int)
    /// The session should parallelise to the maximum possible extent.
    case unlimited
    
    /// The session should intelligently select a concurrency level.
    public static var automatic: Self {
        .unlimited
    }
}


/// An error which can occur when starting a ``BulkExportSession``.
public enum StartSessionError: Error {
    /// Attempted to `start()` a session which is already running.
    case alreadyRunning
    /// Attempted to `start()` a terminated session, which isn't allowed.
    case isTerminated
}


/// Protocol modeling a type-erased ``BulkExportSession``
///
/// ## Topics
/// ### Instance Properties
/// - ``sessionId``
/// - ``state``
/// - ``pendingBatches``
/// - ``completedBatches``
/// - ``failedBatches``
/// - ``numTotalBatches``
/// - ``numProcessedBatches``
/// - ``progress``
/// ### Instance Methods
/// - ``start(retryFailedBatches:concurrencyLevel:)``
/// - ``pause()``
/// ### Other
/// - ``GroveHealthKitBulkExport/==(_:_:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol BulkExportSession<Processor>: AnyObject, Hashable, Sendable, Observable {
    /// The session's ``BatchProcessor``
    associatedtype Processor: BatchProcessor
    
    /// The session's unique identifier
    var sessionId: BulkExportSessionIdentifier { get }
    /// The current state of the export session.
    @MainActor var state: BulkExportSessionState { get }
    
    /// The session's pending batches.
    ///
    /// If the session is running, this will include the batch currently being processed.
    @MainActor var pendingBatches: [ExportBatch] { get }
    /// The session's completed batches.
    @MainActor var completedBatches: [ExportBatch] { get }
    /// The session's failed batches.
    @MainActor var failedBatches: [ExportBatch] { get }
    /// The total number of batches in the session.
    @MainActor var numTotalBatches: Int { get }
    
    /// Progress while the session is running; `nil` otherwise.
    @MainActor var progress: BulkExportSessionProgress? { get }
    
    /// Starts the session.
    ///
    /// Samples may repeat across batches; deduplicate within each participant’s data.
    /// Progress is checkpointed for restoration across launches. After a write failure, retrying the live
    /// session preserves its completed batches; terminating the app loses any unsaved progress.
    /// Pass `retryFailedBatches: true` to retry failed batches as well as checkpoint persistence.
    /// Restoration may repeat batches whose completion was not saved.
    ///
    /// Attempting to start a session that is already running will result in a ``StartSessionError/alreadyRunning`` error.
    ///
    /// - returns: an `AsyncStream` that can be used to access the individual batch results resulting from processing the export session.
    @MainActor func start(
        retryFailedBatches: Bool,
        concurrencyLevel: BulkExportConcurrencyLevel
    ) throws(StartSessionError) -> AsyncStream<Processor.Output>
    
    /// Requests a pause and waits for active workers and the final checkpoint attempt.
    ///
    /// The pause is not necessarily immediate: a running ``BatchProcessor`` may take time to respond to cancellation.
    /// Inspect `state` afterward: a checkpoint failure takes precedence over the requested pause.
    ///
    /// - Note: The call returns once active work and checkpoint persistence have settled.
    ///     Place it inside a `Task` if the caller should continue without waiting.
    @MainActor func pause() async
    
    /// Irrevocably terminates the session and detaches it from the ``BulkHealthExporter``.
    ///
    /// Waits for active work and pending checkpoint writes before returning.
    /// A long-running ``BatchProcessor`` can delay termination while it responds to cancellation.
    ///
    /// - Note: Place the call inside a `Task` if the caller should continue without waiting.
    @MainActor func _terminate() async // swiftlint:disable:this identifier_name
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BulkExportSession {
    /// The number of batches the session has already processed, i.e. the combined number of completed and failed batches.
    @MainActor public var numProcessedBatches: Int {
        completedBatches.count + failedBatches.count
    }
    
    /// Starts the session.
    ///
    /// Attempting to start a session that is already running will result in a ``StartSessionError/alreadyRunning`` error.
    @_disfavoredOverload
    @MainActor
    public func start(
        retryFailedBatches: Bool = false,
        concurrencyLevel: BulkExportConcurrencyLevel = .automatic
    ) throws(StartSessionError) -> AsyncStream<Processor.Output> {
        try start(retryFailedBatches: retryFailedBatches, concurrencyLevel: concurrencyLevel)
    }
    
    /// Starts the session.
    ///
    /// Attempting to start a session that is already running will result in a ``StartSessionError/alreadyRunning`` error.
    @MainActor
    public func start(
        retryFailedBatches: Bool = false,
        concurrencyLevel: BulkExportConcurrencyLevel = .automatic
    ) throws(StartSessionError) where Processor.Output == Void {
        let _: AsyncStream = try start(retryFailedBatches: retryFailedBatches, concurrencyLevel: concurrencyLevel)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BulkExportSession {
    /// Compares two Bulk Export Sessions for equality.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    /// Hashes a Bulk Export Session
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// Compares two Bulk Export Sessions for equality.
@available(iOS 18, macOS 15, watchOS 11, *)
public func == (lhs: any BulkExportSession, rhs: any BulkExportSession) -> Bool { // swiftlint:disable:this static_operator
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

#endif
