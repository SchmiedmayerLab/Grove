//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

private import Foundation
private import OSLog
import SensorKit
private import SpeziFoundation


@available(iOS 18.0, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by #samples.
    final class SampleCountBasedFetcher: AsyncIteratorProtocol {
        private let anchor: ManagedQueryAnchor
        private let reader: SRSensorReader
        private let delegate: FetchDelegate<Sample> // swiftlint:disable:this weak_delegate
        private let device: SRDevice
        private var isFetching = false
        
        init(
            sensor: Sensor<Sample>,
            batchSize: Int,
            anchor: ManagedQueryAnchor,
            device: SRDevice
        ) {
            self.anchor = anchor
            self.device = device
            self.reader = SRSensorReader(sensor)
            self.delegate = FetchDelegate(
                sensor: sensor,
                deviceInfo: SensorKit.DeviceInfo(device),
                batchSize: batchSize,
                anchor: anchor
            )
            self.reader.delegate = self.delegate
        }
        
        func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            guard !Task.isCancelled else {
                return nil
            }
            if !isFetching {
                isFetching = true
                let fetchRequest = SRFetchRequest()
                fetchRequest.device = device
                fetchRequest.from = SRAbsoluteTime(try anchor.value.timestamp)
                fetchRequest.to = .current()
                reader.fetch(fetchRequest)
            }
            return try await delegate.nextBatch(isolation: actor)
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
    typealias Element = AnchoredFetcher<Sample>.Element
    
    private enum State {
        /// The underlying fetch is still in progress, and the delegate may or may not already be delivering batches to its consumer.
        case fetching
        /// The underlying fetch has been completed, but the final batch hasn't yet been delivered to the consumer.
        case flushing
        /// The underlying SensorKit fetch has failed.
        case failed(any Error)
        /// The delegate is terminated and will never produce any results again.
        case terminated
        
        var isFetching: Bool {
            switch self {
            case .fetching:
                true
            case .flushing, .failed, .terminated:
                false
            }
        }
        
        /// Determines if the state is a valid successor to `prevState`
        func isValidSuccessor(to prevState: State) -> Bool {
            switch (prevState, self) {
            case (.fetching, .fetching), (.flushing, .flushing), (.failed, .failed), (.terminated, .terminated):
                // same-state transition
                true
            case (.fetching, _):
                // fetching -> anywhere
                true
            case (.flushing, .failed), (.flushing, .terminated):
                // flushing -> valid successor
                true
            case (.flushing, .fetching):
                // flushing -> invalid successor
                false
            case (.failed, .terminated):
                true
            case (.failed, .fetching), (.failed, .flushing):
                false
            case (.terminated, .fetching), (.terminated, .flushing), (.terminated, .failed):
                // terminated -> invalid successor
                false
            }
        }
    }
    
    private let logger: Logger
    private let sensor: Sensor<Sample>
    private let deviceInfo: SensorKit.DeviceInfo
    private let batchSize: Int
    private let anchor: ManagedQueryAnchor
    
    /// Protects all mutable state in the object.
    ///
    /// Recursive because `processCurrentSamples`' empty branch calls `stop()` while holding it.
    /// The semaphore wait always happens **outside** the lock (see `processCurrentSamples`), as do the
    /// continuation resumes in `nextBatch`, `stop`, and `failedWithError`.
    /// `processCurrentSamples` resumes while holding the lock, which is safe because `resume` only enqueues
    /// the consumer's task (it never runs it inline), and the lock is recursive.
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
    nonisolated(unsafe) private var state: State = .fetching {
        didSet {
            assert(state.isValidSuccessor(to: oldValue), "Invalid state transition from \(oldValue) to \(state)!")
        }
    }
    
    nonisolated(unsafe) private(set) var samples: [Sample.SafeRepresentation] = []
    nonisolated(unsafe) private(set) var lastSeenTimestamp: SRAbsoluteTime?
    
    private let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) private var nextBatchContinuation: CheckedContinuation<Element?, any Error>?
    
    /// Creates a new instance
    ///
    /// - parameter batchSize: Must be greater than zero.
    init(sensor: Sensor<Sample>, deviceInfo: SensorKit.DeviceInfo, batchSize: Int, anchor: ManagedQueryAnchor) {
        self.logger = Logger(subsystem: "edu.stanford.SpeziSensorKit", category: "\(Self.self)")
        self.sensor = sensor
        self.deviceInfo = deviceInfo
        self.batchSize = batchSize
        self.anchor = anchor
        self.samples.reserveCapacity(batchSize + (batchSize / 5))
        if batchSize <= 0 {
            logger.error("Crated \(Self.self) with invalid batch size (\(batchSize)). This will never yield any samples.")
            state = .terminated
        }
    }
    
    func nextBatch(isolation: isolated (any Actor)?) async throws -> Element? {
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
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
                        continuation.resume(returning: nil)
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
        continuation?.resume(returning: nil)
    }
    
    private func processCurrentSamples() {
        // IMPORTANT: the semaphore wait must happen OUTSIDE the lock, otherwise we'd deadlock
        // with `stop()`: it acquires the lock and then signals the semaphore, but if we held
        // the lock here it could never acquire it to signal us.
        semaphore.wait() // wait for continuation to be ready
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
            return
        }
        if let first = samples.first {
            // samples is not empty
            self.nextBatchContinuation = nil
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
            nextBatchContinuation.resume(returning: (
                SensorKit.BatchInfo(timeRange: timeRange, device: deviceInfo),
                samples
            ))
        } else {
            // samples is empty
            self.nextBatchContinuation = nil
            nextBatchContinuation.resume(returning: nil)
            stop()
        }
        if let lastSeenTimestamp {
            do {
                try anchor.update(QueryAnchor(timestamp: Date(lastSeenTimestamp)))
            } catch {
                logger.error("Failed to update query anchor: \(error)")
            }
        }
        samples.removeAll(keepingCapacity: true)
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        guard lock.withLock({ state.isFetching }) else {
            return false
        }
        do {
            // make sure we properly limit the lifetimes of the on-demand-decoded SRFetchResult sample properties...
            try autoreleasepool {
                let fetchResult = try SensorKit.FetchResult(result, for: sensor)
                let newSamples = SensorKit.FetchResultsIterator(fetchResult).map {
                    (timestamp: $0, sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
                }
                let processed = try Sample.processIntoSafeRepresentation(newSamples)
                lock.lock()
                // re-check under the lock: a deinit-triggered `stop()` may have interleaved since the
                // check above, in which case the batch must be dropped (post-stop, `samples` stays empty).
                if state.isFetching {
                    self.samples.append(contentsOf: processed)
                    lastSeenTimestamp = lastSeenTimestamp.map { max($0, result.timestamp) } ?? result.timestamp
                }
                lock.unlock()
            }
        } catch {
            logger.error("Error processing fetch result: \(error)")
            // we simply skip this result and continue normally
            return true
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
