//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

private import Foundation
private import GroveFoundation
private import OSLog
import SensorKit


@available(iOS 18.0, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by #samples.
    final class SampleCountBasedFetcher: AsyncIteratorProtocol {
        private let anchor: ManagedQueryAnchor
        private let reader: SRSensorReader
        private let delegate: FetchDelegate<Sample> // swiftlint:disable:this weak_delegate
        private let device: SRDevice
        private let startFetch: (SRSensorReader, SRFetchRequest) -> Void
        private var isFetching = false
        private var fetchCursor: QueryAnchor?
        private var outstandingAcknowledgement: QueryAnchor?
        
        init(
            sensor: Sensor<Sample>,
            batchSize: Int,
            anchor: ManagedQueryAnchor,
            device: SRDevice,
            startFetch: @escaping (SRSensorReader, SRFetchRequest) -> Void = { reader, request in
                reader.fetch(request)
            }
        ) {
            self.anchor = anchor
            self.device = device
            self.startFetch = startFetch
            self.reader = SRSensorReader(sensor)
            self.delegate = FetchDelegate(
                sensor: sensor,
                deviceInfo: SensorKit.DeviceInfo(device),
                batchSize: batchSize
            )
            self.reader.delegate = self.delegate
        }

        func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            guard !Task.isCancelled else {
                // NOTE: we must stop the delegate here, rather than simply returning: if the cancellation
                // happened while the consumer was between `next()` calls, no cancellation handler was
                // installed, so nothing else will release a `processCurrentSamples()` that is parked in
                // `semaphore.wait()`, and the underlying fetch would keep running. `stop()` is idempotent.
                delegate.stop()
                return nil
            }
            try acceptOutstandingAcknowledgement()
            try startNativeFetchIfNeeded()
            let delivery = try await delegate.nextBatch(isolation: actor)
            let fetchCursor = try validatedFetchCursor()
            guard let rawElement = delivery.element else {
                return try finishEmptyDelivery(anchor: delivery.anchor, fetchCursor: fetchCursor)
            }
            return try prepareAnchoredBatch(
                rawElement,
                deliveredAnchor: QueryAnchor.requireDeliveryAnchor(delivery.anchor),
                fetchCursor: fetchCursor
            )
        }

        private func acceptOutstandingAcknowledgement() throws {
            guard let outstandingAcknowledgement else {
                return
            }
            guard try anchor.value == outstandingAcknowledgement else {
                throw SensorKit.QueryAnchorAcknowledgementError.outstandingBatch
            }
            fetchCursor = outstandingAcknowledgement
            self.outstandingAcknowledgement = nil
        }

        private func finishEmptyDelivery(anchor deliveredAnchor: QueryAnchor?, fetchCursor: QueryAnchor) throws -> Element? {
            guard fetchCursor.pendingBatch == nil else {
                throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
            }
            if let deliveredAnchor {
                let desiredAnchor = fetchCursor.advancedPastEmptyRange(to: deliveredAnchor.timestamp)
                guard try anchor.update(from: fetchCursor, to: desiredAnchor) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
                self.fetchCursor = desiredAnchor
            }
            return nil
        }

        private func prepareAnchoredBatch(
            _ rawElement: FetchDelegate<Sample>.RawElement,
            deliveredAnchor: QueryAnchor,
            fetchCursor: QueryAnchor
        ) throws -> Element {
            let pendingBatch = QueryAnchor.PendingBatch.sampleCount(
                deliveryTimestamp: deliveredAnchor.timestamp,
                sampleCount: rawElement.samples.count
            )
            let pendingAnchor: QueryAnchor
            if let persistedPending = fetchCursor.pendingBatch {
                guard persistedPending == pendingBatch else {
                    throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                }
                pendingAnchor = fetchCursor
            } else {
                pendingAnchor = fetchCursor.preparing(pendingBatch)
                guard try anchor.update(from: fetchCursor, to: pendingAnchor) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
            }
            let desiredAnchor = try pendingAnchor.committingPendingBatch()
            let anchor = self.anchor
            let acknowledgement = SensorKit.QueryAnchorAcknowledgement {
                guard try anchor.update(from: pendingAnchor, to: desiredAnchor) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
            }
            outstandingAcknowledgement = desiredAnchor
            return SensorKit.AnchoredBatch(
                info: SensorKit.BatchInfo(
                    timeRange: rawElement.timeRange,
                    device: rawElement.device,
                    acquisitionBatch: fetchCursor.acquisitionBatchCoordinate
                ),
                samples: rawElement.samples,
                acknowledgement: acknowledgement
            )
        }

        private func startNativeFetchIfNeeded() throws {
            guard !isFetching else {
                return
            }
            let fetchCursor = try anchor.value
            if let pendingBatch = fetchCursor.pendingBatch {
                guard pendingBatch.mode == .sampleCount,
                      pendingBatch.sampleCount > 0 else {
                    throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                }
                delegate.configureBatchSize(pendingBatch.sampleCount)
            }
            self.fetchCursor = fetchCursor
            isFetching = true
            let fetchRequest = SRFetchRequest()
            fetchRequest.device = device
            fetchRequest.from = SRAbsoluteTime(fetchCursor.timestamp)
            fetchRequest.to = .current()
            startFetch(reader, fetchRequest)
        }

        private func validatedFetchCursor() throws -> QueryAnchor {
            guard let fetchCursor, try anchor.value == fetchCursor else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
            return fetchCursor
        }

        func processForTesting(sample object: AnyObject, timestamp: SRAbsoluteTime) -> Bool {
            delegate.process(sample: object, timestamp: timestamp)
        }

        func startNativeFetchForTesting() throws {
            try startNativeFetchIfNeeded()
        }

        func validateFetchCursorForTesting() throws {
            _ = try validatedFetchCursor()
        }

        func validateDeliveryAnchorForTesting(_ deliveredAnchor: QueryAnchor?) throws {
            _ = try QueryAnchor.requireDeliveryAnchor(deliveredAnchor)
        }

        /// Explicit witness for the legacy `next()` requirement.
        ///
        /// Needed to work around https://github.com/swiftlang/swift/issues/87849
        /// Can be removed once the deployment target is iOS 18.4+
        @inlinable
        func next() async throws(Failure) -> Element? {
            try await next(isolation: nil)
        }
        
        deinit {
            // if the iterator is destroyed, we explicitly tell the fetch delegate to stop.
            // this is required to prevent SensorKit from providing us more and more data in
            // a situation where the loop stopped early (eg because of a break or return) rather
            // than because the iterator was exhausted
            delegate.stop()
        }
    }
}

@available(iOS 18, *)
private final class FetchDelegate<Sample: SensorKitSampleProtocol>: NSObject, SRSensorReaderDelegate, Sendable {
    typealias RawElement = SampleCountRawElement<Sample>
    typealias Delivery = (element: RawElement?, anchor: QueryAnchor?)
    private let logger: Logger
    private let sensor: Sensor<Sample>
    private let deviceInfo: SensorKit.DeviceInfo
    /// Protected by `lock`; a persisted pending-batch size is installed before native fetching starts.
    nonisolated(unsafe) private var batchSize: Int
    /// Protects all mutable state in the object.
    ///
    /// Recursive because `takeNextBatchResumption`'s empty branch calls `stop()` while holding it.
    /// The semaphore wait always happens **outside** the lock (see `processCurrentSamples`), and so does
    /// **every** continuation resume (`nextBatch`, `stop`, `failedWithError`, and `processCurrentSamples`
    /// via `takeNextBatchResumption`).
    /// Resuming under the lock is not merely undesirable but an actual deadlock: a cross-thread `resume`
    /// acquires the consumer task's status-record lock, and `swift_task_cancel` acquires that same lock
    /// before running our cancellation handler, which then wants this lock (ABBA). Note that recursion
    /// does not help here, since the two acquisitions are on different threads.
    ///
    /// Context: the state held by instances of this class is accessed from both the Swift Concurrency consumer thread
    /// (`nextBatch()`, `stop()` via `SampleCountBasedFetcher.deinit`) and SensorKit's callback thread
    /// (`didFetchResult`, `didCompleteFetch`, `failedWithError`);
    /// as these methods may end up getting called concurrently, we need to be able to cope with that.
    private let lock = NSRecursiveLock()
    
    /// The current state of the fetch delegate.
    ///
    /// Protected by `lock`.
    ///
    /// Once the state leaves `.fetching` or `.flushing`, it never returns to either of these states.
    /// Once it reaches `.terminated`, it will remain in that state forever.
    nonisolated(unsafe) private var state: SampleCountFetchState = .fetching {
        didSet {
            assert(state.isValidSuccessor(to: oldValue), "Invalid state transition from \(oldValue) to \(state)!")
        }
    }
    
    nonisolated(unsafe) private(set) var samples: [Sample.SafeRepresentation] = []
    nonisolated(unsafe) private(set) var lastSeenTimestamp: SRAbsoluteTime?
    
    private let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) private var nextBatchContinuation: CheckedContinuation<Delivery, any Error>?
    
    /// Creates a new instance
    ///
    /// - parameter batchSize: Must be greater than zero.
    init(sensor: Sensor<Sample>, deviceInfo: SensorKit.DeviceInfo, batchSize: Int) {
        self.logger = Logger(subsystem: "org.grovealliance.sensorKit", category: "\(Self.self)")
        self.sensor = sensor
        self.deviceInfo = deviceInfo
        self.batchSize = batchSize
        self.samples.reserveCapacity(batchSize + (batchSize / 5))
        if batchSize <= 0 {
            logger.error("Crated \(Self.self) with invalid batch size (\(batchSize)). This will never yield any samples.")
            state = .terminated
        }
    }

    /// Reinstates the exact delivery boundary persisted before a previously yielded batch.
    func configureBatchSize(_ batchSize: Int) {
        precondition(batchSize > 0)
        lock.withLock {
            precondition(samples.isEmpty && lastSeenTimestamp == nil)
            self.batchSize = batchSize
            samples.reserveCapacity(batchSize + (batchSize / 5))
        }
    }
    
    func nextBatch(isolation: isolated (any Actor)?) async throws -> Delivery {
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Delivery, any Error>) in
                    lock.lock()
                    switch state {
                    case .fetching, .flushing:
                        // NOTE: the state may transition away from `.fetching` or `.flushing` at any point
                        // after we release the lock (SensorKit's callbacks run on their own thread);
                        // the termination paths are responsible for resuming a parked continuation, so this is safe.
                        // this can only fire on consumer misuse (two concurrent `next()` calls on the same
                        // iterator (which should be impossible as the iterator is not Sendable));
                        // it is inside the lock, so it can no longer fire spuriously on the
                        // SensorKit-callback races that the old unguarded preconditions crashed on.
                        precondition(nextBatchContinuation == nil, "\(sensor.displayName)")
                        nextBatchContinuation = continuation
                        lock.unlock()
                        semaphore.signal() // signal that continuation is ready
                    case .failed(let error):
                        // the fetch has failed: end the iteration.
                        state = .terminated
                        lock.unlock()
                        continuation.resume(throwing: error)
                    case .terminated:
                        // the fetch has already completed, or been stopped: end the iteration.
                        lock.unlock()
                        continuation.resume(returning: (nil, nil))
                    }
                }
            },
            onCancel: {
                stop()
            },
            isolation: isolation
        )
    }
    
    func stop() {
        lock.lock()
        samples.removeAll()
        lastSeenTimestamp = nil
        let continuation = nextBatchContinuation
        nextBatchContinuation = nil
        switch state {
        case .failed:
            // keep as-is, so that the next `nextBatch()` call correctly can re-throw the error
            break
        case .fetching, .flushing, .terminated:
            state = .terminated
        }
        lock.unlock()
        // NOTE: the termination paths can signal more than once, inflating the semaphore's permit count;
        // this is safe because any consumer of a stale permit lands in `processCurrentSamples`'
        // nil-continuation early return.
        semaphore.signal() // in case the process function is currently waiting on the semaphore...
        // a parked consumer must never be left hanging, so we resume it outside the lock.
        // (in the deinit-triggered stop this is always nil, since the consumer is the one deiniting us;
        // when called from `processCurrentSamples`' empty branch, the calling frame still holds the
        // recursive lock and has already taken the continuation, so it is nil there as well.)
        continuation?.resume(returning: (nil, nil))
    }
    
    private func processCurrentSamples() {
        // IMPORTANT: the semaphore wait must happen OUTSIDE the lock, otherwise we'd deadlock
        // with `stop()`: it acquires the lock and then signals the semaphore, but if we held
        // the lock here it could never acquire it to signal us.
        semaphore.wait() // wait for continuation to be ready
        // IMPORTANT: the resume must also happen OUTSIDE the lock; see `takeNextBatchResumption()`.
        if let (continuation, value) = takeNextBatchResumption() {
            continuation.resume(returning: value)
        }
    }

    /// Performs the locked half of ``processCurrentSamples()``: advances the state machine, takes ownership
    /// of the parked continuation, and computes the value that continuation should be resumed with.
    ///
    /// - Important: the caller must resume the returned continuation only *after* this function has returned,
    ///     i.e. once `lock` has been released again. Resuming a continuation whose task is parked on another
    ///     thread requires that task's status-record lock, and `swift_task_cancel` acquires that very lock
    ///     *before* invoking our cancellation handler, which in turn wants `lock`. Resuming while holding
    ///     `lock` therefore deadlocks (ABBA) against a concurrent cancellation of the consuming task.
    /// - returns: the parked continuation and the value to resume it with, or `nil` if no consumer is parked.
    private func takeNextBatchResumption() -> (CheckedContinuation<Delivery, any Error>, Delivery)? {
        lock.lock()
        defer {
            lock.unlock()
        }
        switch state {
        case .flushing:
            // if we're flushing the final batch, we want to terminate the delegate as part of the operation.
            state = .terminated
        case .fetching, .failed, .terminated:
            break
        }
        guard let nextBatchContinuation else {
            return nil
        }
        self.nextBatchContinuation = nil
        let value: RawElement?
        if let first = samples.first {
            // samples is not empty
            // NOTE: most of the time, SensorKit queries return their samples in ascending chronological order,
            // which, were it guaranteed behaviour, would allow us to simply do `first.timeRange.lowerBound..<last.timeRange.lowerBound`.
            // but, it is not guaranteed, and sometimes the samples are not ordered, and as a result we need to do this ugly O(n) here...
            let timeRange = { () -> Range<Date> in
                // note that we intentionally use the lower bound of the last sample's time range,
                // in order to make the batch's time range match the fetched time range, as opposed to the represented time range.
                // (otherwise, using the batch's time ranges to perform follow up fetches could lead to missed samples...)
                var start = first.timeRange.lowerBound
                var end = start
                for sample in samples.dropFirst() {
                    let sampleDate = sample.timeRange.lowerBound
                    start = min(start, sampleDate)
                    end = max(end, sampleDate)
                }
                return start..<end
            }()
            value = RawElement(timeRange: timeRange, device: deviceInfo, samples: samples)
        } else {
            // samples is empty
            value = nil
            // NOTE: safe to call while holding the (recursive) lock: we have already taken the continuation
            // above, so `stop()`'s own resume is a no-op and cannot resume anything under the lock.
            stop()
        }
        let deliveredAnchor = lastSeenTimestamp.map { QueryAnchor(timestamp: Date($0)) }
        lastSeenTimestamp = nil
        samples.removeAll(keepingCapacity: true)
        return (nextBatchContinuation, (value, deliveredAnchor))
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        // Keep the materialized native sample's lifetime scoped to SensorKit's callback queue.
        autoreleasepool {
            process(timestamp: result.timestamp) {
                try SensorKit.FetchResult(result, for: sensor)
            }
        }
    }

    func process(sample object: AnyObject, timestamp: SRAbsoluteTime) -> Bool {
        process(timestamp: timestamp) {
            try SensorKit.FetchResult(sample: object, timestamp: timestamp, for: sensor)
        }
    }

    private func process(
        timestamp: SRAbsoluteTime,
        fetchResult: () throws -> SensorKit.FetchResult<Sample>
    ) -> Bool {
        guard lock.withLock({ state.isFetching }) else {
            return false
        }
        do {
            let fetchResult = try fetchResult()
            let newSamples = SensorKit.FetchResultsIterator(fetchResult).map {
                (timestamp: $0, sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
            }
            let processed = try Sample.processIntoSafeRepresentation(newSamples)
            lock.lock()
            // re-check under the lock: a deinit-triggered `stop()` may have interleaved since the
            // check above, in which case the batch must be dropped (post-stop, `samples` stays empty).
            if state.isFetching {
                self.samples.append(contentsOf: processed)
                lastSeenTimestamp = lastSeenTimestamp.map { max($0, timestamp) } ?? timestamp
            }
            lock.unlock()
        } catch {
            logger.error("SensorKit batch processing failed; error type: \(String(reflecting: type(of: error)), privacy: .public)")
            // Advancing past a malformed native result would make a later acknowledged batch
            // permanently skip it. Terminate and surface the error while the durable cursor stays.
            fail(error)
            return false
        }
        let batchIsFull = lock.withLock {
            samples.count >= batchSize
        }
        if batchIsFull {
            processCurrentSamples()
        }
        return lock.withLock { state.isFetching }
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, failedWithError error: any Error) {
        fail(error)
    }

    private func fail(_ error: any Error) {
        lock.lock()
        switch state {
        case .fetching, .flushing:
            // Policy: a failure arriving during the final flush wins; remaining samples are discarded.
            if let continuation = exchange(&nextBatchContinuation, with: nil) {
                state = .terminated
                lock.unlock()
                continuation.resume(throwing: error)
            } else {
                // no consumer waiting; deliver the error on its next call.
                state = .failed(error)
                lock.unlock()
            }
        case .failed, .terminated:
            // terminal states are absorbing; keep the original error.
            lock.unlock()
        }
        // stop() is idempotent and terminal-state-preserving (its switch keeps `.failed`);
        // calling it unconditionally keeps the cleanup guarantee local to this function
        // instead of relying on every terminal path having already cleaned up.
        stop()
    }

    func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
        lock.lock()
        switch state {
        case .fetching:
            state = .flushing
            lock.unlock()
            processCurrentSamples()
        case .flushing, .failed, .terminated:
            // duplicate/late terminal callback: terminal states are absorbing, and a pending
            // `.failed` error must not be clobbered. Don't run `processCurrentSamples()` here:
            // with no flush owed there may be no semaphore permit coming, and its `wait()`
            // would block SensorKit's callback thread.
            lock.unlock()
        }
        // stop() is idempotent and terminal-state-preserving (its switch keeps `.failed`);
        // calling it unconditionally keeps the cleanup guarantee local to this function.
        stop()
    }
}
