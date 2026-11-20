//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order file_length

private import Foundation
private import GroveFoundation
private import OSLog
import SensorKit


@available(iOS 18.0, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by #samples.
    final class SampleCountBasedFetcher: AsyncIteratorProtocol {
        private let anchor: ManagedQueryAnchor
        private let sensorIdentifier: String
        private let quarantineDuration: TimeInterval
        private let initialStartDate: Date?
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
            initialStartDate: Date? = nil,
            ecgProcessingLimits: SensorKitECGProcessingLimits = .init(),
            startFetch: @escaping (SRSensorReader, SRFetchRequest) -> Void = { reader, request in
                reader.fetch(request)
            }
        ) {
            self.anchor = anchor
            self.initialStartDate = initialStartDate
            self.sensorIdentifier = sensor.id
            self.quarantineDuration = sensor.dataQuarantineDuration.timeInterval
            self.device = device
            self.startFetch = startFetch
            self.reader = SRSensorReader(sensor)
            self.delegate = FetchDelegate(
                sensor: sensor,
                deviceInfo: SensorKit.DeviceInfo(device),
                batchSize: batchSize,
                ecgProcessingLimits: ecgProcessingLimits
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
            guard delivery.element != nil || !Task.isCancelled else {
                // A cancellation stops the fetch before its batch. Like a cancellation between `next()` calls, it ends
                // the iteration; a persisted pending batch stays for the next fetch.
                return nil
            }
            let fetchCursor = try validatedFetchCursor()
            guard let rawElement = delivery.element else {
                // A fetch that delivers nothing states no boundary, so the cursor stays. A persisted pending batch
                // must be delivered again, so an empty fetch does not resolve it.
                guard fetchCursor.pendingBatch == nil else {
                    throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                }
                return nil
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

        private func prepareAnchoredBatch(
            _ rawElement: FetchDelegate<Sample>.RawElement,
            deliveredAnchor: QueryAnchor,
            fetchCursor: QueryAnchor
        ) throws -> Element {
            let pendingBatch = QueryAnchor.PendingBatch.sampleCount(
                deliveryTimestamp: deliveredAnchor.timestamp,
                sampleCount: rawElement.samples.count,
                nativeTimestamp: deliveredAnchor.nativeTimestamp
            )
            let pendingAnchor: QueryAnchor
            if let persistedPending = fetchCursor.pendingBatch {
                guard persistedPending.matchesSampleCountDelivery(pendingBatch) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                }
                pendingAnchor = fetchCursor
            } else {
                pendingAnchor = fetchCursor.preparing(pendingBatch)
            }
            // Everything that can fail is derived before the pending batch is persisted, so a failure never leaves a
            // pending batch that no later fetch can deliver.
            let replayToken = try SensorKit.BatchReplayToken(
                sensorIdentifier: sensorIdentifier, deviceProductType: device.productType, anchor: pendingAnchor
            )
            let desiredAnchor = try pendingAnchor.committingPendingBatch()
            guard try anchor.update(from: fetchCursor, to: pendingAnchor) else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
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
                    sourceDevices: rawElement.sourceDevices,
                    sourceDevicesSuppliedEverySample: rawElement.sourceDevicesSuppliedEverySample,
                    acquisitionBatch: pendingAnchor.acquisitionBatchCoordinate,
                    replayToken: replayToken
                ),
                samples: rawElement.samples,
                acknowledgement: acknowledgement
            )
        }

        private func startNativeFetchIfNeeded() throws {
            guard !isFetching else {
                return
            }
            var fetchCursor = try anchor.value
            let reference = SRAbsoluteTime.current()
            if fetchCursor.pendingBatch == nil {
                let start = fetchCursor.timestamp == .distantPast ? initialStartDate ?? .distantPast : fetchCursor.timestamp
                let native = fetchCursor.nativeTimestamp ?? SRAbsoluteTime(start).rawValue
                let clock = QueryNativeClock(nativeReferenceBits: reference.rawValue.bitPattern, wallReference: Date(reference))
                guard native.isFinite, clock.isValid else {
                    throw SensorKit.AnchoredFetchError.invalidNativeClock
                }
                let retained = fetchCursor.retainingNativeTimestamp(native, clock: clock)
                guard try anchor.update(from: fetchCursor, to: retained) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
                fetchCursor = retained
            }
            // SensorKit returns no data newer than the quarantine cutoff, so a session that ends there may be cut off.
            delegate.configure(
                nativeClock: fetchCursor.nativeClock,
                ecgHoldCutoff: reference.rawValue - quarantineDuration - SensorKitECGAssembly.holdInterval
            )
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
            // The cursor is the boundary of the last acknowledged batch. The batches assume that SensorKit returns only
            // results after `from`, in ascending timestamp order.
            fetchRequest.from = fetchCursor.nativeTimestamp.map(SRAbsoluteTime.init(rawValue:)) ?? SRAbsoluteTime(fetchCursor.timestamp)
            fetchRequest.to = reference
            startFetch(reader, fetchRequest)
        }

        private func validatedFetchCursor() throws -> QueryAnchor {
            guard let fetchCursor, try anchor.value == fetchCursor else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
            return fetchCursor
        }

        func processForTesting(
            sample object: AnyObject,
            timestamp: SRAbsoluteTime,
            sourceDevice: SensorKit.SourceDeviceInfo? = nil
        ) -> Bool {
            delegate.process(sample: object, timestamp: timestamp, sourceDevice: sourceDevice)
        }

        func processECGGroupsForTesting(
            _ groups: [SensorKitECGSession.InputGroup],
            timestamp: SRAbsoluteTime,
            sourceDevice: SensorKit.SourceDeviceInfo? = nil
        ) -> Bool {
            delegate.processECGGroups(groups, timestamp: timestamp, sourceDevice: sourceDevice)
        }

        func loggedSkippedECGSessionCountForTesting() -> Int {
            delegate.loggedSkippedECGSessionCount()
        }

        func stopForTesting() {
            delegate.stop()
        }

        func completeFetchForTesting() {
            delegate.sensorReader(reader, didCompleteFetch: SRFetchRequest())
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

/// The peripherals a set of native fetch results named.
@available(iOS 18, *)
private struct SourceDevices {
    /// The named peripherals, in the order SensorKit first named them.
    private(set) var named: [SensorKit.SourceDeviceInfo] = []
    /// Whether a result named no peripheral.
    private(set) var hasUnnamedResult = false

    mutating func add(_ device: SensorKit.SourceDeviceInfo?) {
        if let device {
            if !named.contains(device) {
                named.append(device)
            }
        } else {
            hasUnnamedResult = true
        }
    }

    mutating func formUnion(_ other: Self) {
        other.named.forEach { add($0) }
        hasUnnamedResult = hasUnnamedResult || other.hasUnnamedResult
    }
}


/// One native ECG fetch result, kept while a batch can still end before it.
@available(iOS 18, *)
private struct ECGResult {
    let groups: [SensorKitECGSession.InputGroup]
    let timestamp: SRAbsoluteTime
    let sourceDevice: SensorKit.SourceDeviceInfo?
    /// The zero-based order in which the result arrived in the native fetch.
    let number: Int
}


/// A point at which the current batch can end.
@available(iOS 18, *)
private struct BatchEnd {
    /// How many of the collected samples the batch holds.
    let sampleCount: Int
    /// The largest native timestamp of a result with data when the last of those samples was added.
    let boundary: SRAbsoluteTime
    /// The peripherals of the fetch results received up to the boundary.
    let sourceDevices: SourceDevices
}


/// Collects the samples of one native fetch into batches.
///
/// A batch ends at a batch end: a number of samples and the largest native timestamp of a result with data received
/// when the last of them was added, recorded when a fetch from that timestamp would read again everything the batch leaves out. A batch end
/// is a candidate until a result with a later timestamp or the end of the fetch confirms it; a result with the same or
/// an earlier timestamp withdraws it, since a fetch from that timestamp would not read the result again. Only a
/// confirmed batch end is delivered. Batch size, ECG limits and the end of the fetch only decide when the batch is
/// delivered. After a delivery the delegate starts over as a fetch from the boundary does and processes the retained
/// results after the boundary again, so its state never depends on where an earlier batch ended. A later fetch that
/// starts at the same cursor with the batch's sample count as its batch size therefore delivers the same batch,
/// whatever newer data SensorKit returns by then, as long as SensorKit returns the same results in the same order.
///
/// The cursor is a native timestamp: results are expected in ascending timestamp order, and a fetch is expected to
/// return only results after its start.
@available(iOS 18, *)
private final class FetchDelegate<Sample: SensorKitSampleProtocol>: NSObject, SRSensorReaderDelegate, Sendable {
    typealias RawElement = SampleCountRawElement<Sample>
    typealias Delivery = (element: RawElement?, anchor: QueryAnchor?)
    private struct Resumption {
        let continuation: CheckedContinuation<Delivery, any Error>
        let delivery: Delivery
        /// The retained results after the delivered batch's boundary, to process again.
        let resultsToProcess: [ECGResult]
    }

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
    
    nonisolated(unsafe) private var nativeClock: QueryNativeClock?
    private let ecgProcessingLimits: SensorKitECGProcessingLimits
    nonisolated(unsafe) private var ecgAssembly: SensorKitECGAssembly
    /// An unfinished ECG session whose latest native timestamp is earlier than this is finished when the fetch
    /// completes; a later one is held for the next fetch.
    nonisolated(unsafe) private var ecgHoldCutoff = -Double.infinity
    /// The samples collected since the last delivered batch.
    nonisolated(unsafe) private var samples: [Sample.SafeRepresentation] = []
    /// The largest native timestamp of a result with data when `samples` last grew.
    nonisolated(unsafe) private var boundaryTimestamp: SRAbsoluteTime?
    /// Where the current batch can end, confirmed by a later result; a delivery takes the samples up to it.
    nonisolated(unsafe) private var batchEnd: BatchEnd?
    /// A later batch end at the latest result's timestamp, which a result with a later timestamp confirms.
    nonisolated(unsafe) private var candidateBatchEnd: BatchEnd?
    /// The ECG results received after `batchEnd`'s boundary, or since `samples` first grew without one.
    nonisolated(unsafe) private var resultsAfterBatchEnd: [ECGResult] = []
    /// The peripherals of the fetch results received up to the boundary.
    nonisolated(unsafe) private var sourceDevices = SourceDevices()
    /// The peripherals of the fetch results received since `samples` last grew. A fetch from the boundary reads those
    /// results again, so they belong to the next batch.
    nonisolated(unsafe) private var trailingSourceDevices = SourceDevices()
    /// The largest native timestamp of a result with data in this fetch, or the boundary of the last delivered batch.
    /// An ECG result that carries no data of a session the fetch is assembling doesn't count.
    nonisolated(unsafe) private var lastSeenTimestamp: SRAbsoluteTime?
    /// The number of ECG results received in this native fetch.
    nonisolated(unsafe) private var receivedECGResultCount = 0
    /// The last step of ECG processing whose skipped sessions were logged: `2 * number` of its result for the sessions
    /// it supersedes, `2 * number + 1` for the sessions it adds, or `.max` for the end of the fetch. Processing a result
    /// again, after a delivery or to make room, repeats logged steps.
    nonisolated(unsafe) private var lastLoggedECGStep = -1
    /// The skipped ECG sessions logged in this native fetch, for tests.
    nonisolated(unsafe) private var skippedECGSessionLogCount = 0
    
    private let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) private var nextBatchContinuation: CheckedContinuation<Delivery, any Error>?
    
    /// Creates a new instance
    ///
    /// - parameter batchSize: Must be greater than zero.
    init(
        sensor: Sensor<Sample>, deviceInfo: SensorKit.DeviceInfo, batchSize: Int, ecgProcessingLimits: SensorKitECGProcessingLimits
    ) {
        self.ecgProcessingLimits = ecgProcessingLimits
        self.ecgAssembly = SensorKitECGAssembly(limits: ecgProcessingLimits)
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

    func configure(nativeClock: QueryNativeClock?, ecgHoldCutoff: Double) {
        lock.withLock {
            self.nativeClock = nativeClock
            self.ecgHoldCutoff = ecgHoldCutoff
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
        boundaryTimestamp = nil
        batchEnd = nil
        candidateBatchEnd = nil
        resultsAfterBatchEnd.removeAll()
        ecgAssembly = SensorKitECGAssembly(limits: ecgProcessingLimits)
        sourceDevices = SourceDevices()
        trailingSourceDevices = SourceDevices()
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
    
    /// Delivers the current batch to the consumer, waiting for it to ask.
    ///
    /// - Returns: The retained results after the batch's boundary, which the caller processes again.
    @discardableResult
    private func processCurrentSamples() -> [ECGResult] {
        // IMPORTANT: the semaphore wait must happen OUTSIDE the lock, otherwise we'd deadlock
        // with `stop()`: it acquires the lock and then signals the semaphore, but if we held
        // the lock here it could never acquire it to signal us.
        semaphore.wait() // wait for continuation to be ready
        // IMPORTANT: the resume must also happen OUTSIDE the lock; see `takeNextBatchResumption()`.
        guard let resumption = takeNextBatchResumption() else {
            return []
        }
        resumption.continuation.resume(returning: resumption.delivery)
        return resumption.resultsToProcess
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
    private func takeNextBatchResumption() -> Resumption? {
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
        guard let batchEnd, let first = samples.first else {
            // No batch can end here, so nothing is delivered and the cursor stays where it is.
            // NOTE: safe to call while holding the (recursive) lock: we have already taken the continuation
            // above, so `stop()`'s own resume is a no-op and cannot resume anything under the lock.
            stop()
            return Resumption(continuation: nextBatchContinuation, delivery: (nil, nil), resultsToProcess: [])
        }
        let delivered = Array(samples.prefix(batchEnd.sampleCount))
        // NOTE: most of the time, SensorKit queries return their samples in ascending chronological order,
        // which, were it guaranteed behaviour, would allow us to simply do `first.timeRange.lowerBound..<last.timeRange.lowerBound`.
        // but, it is not guaranteed, and sometimes the samples are not ordered, and as a result we need to do this ugly O(n) here...
        let timeRange = { () -> Range<Date> in
            // note that we intentionally use the lower bound of the last sample's time range,
            // in order to make the batch's time range match the fetched time range, as opposed to the represented time range.
            // (otherwise, using the batch's time ranges to perform follow up fetches could lead to missed samples...)
            var start = first.timeRange.lowerBound
            var end = start
            for sample in delivered.dropFirst() {
                let sampleDate = sample.timeRange.lowerBound
                start = min(start, sampleDate)
                end = max(end, sampleDate)
            }
            return start..<end
        }()
        let value = RawElement(
            timeRange: timeRange,
            device: deviceInfo,
            sourceDevices: batchEnd.sourceDevices.named,
            sourceDevicesSuppliedEverySample: !batchEnd.sourceDevices.named.isEmpty && !batchEnd.sourceDevices.hasUnnamedResult,
            samples: delivered
        )
        let deliveredAnchor = QueryAnchor(
            timestamp: nativeClock?.date(for: batchEnd.boundary.rawValue) ?? Date(batchEnd.boundary),
            nativeTimestampBits: batchEnd.boundary.rawValue.bitPattern
        )
        // The delegate starts over as a fetch from the boundary does. The caller processes the retained results after
        // the boundary again, which brings back the samples and unfinished ECG sessions the batch left out.
        let resultsToProcess = resultsAfterBatchEnd
        startOver(at: batchEnd.boundary)
        return Resumption(continuation: nextBatchContinuation, delivery: (value, deliveredAnchor), resultsToProcess: resultsToProcess)
    }

    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        // Keep the materialized native sample's lifetime scoped to SensorKit's callback queue.
        autoreleasepool {
            process(timestamp: result.timestamp) {
                try SensorKit.FetchResult(result, for: sensor)
            }
        }
    }

    func process(sample object: AnyObject, timestamp: SRAbsoluteTime, sourceDevice: SensorKit.SourceDeviceInfo? = nil) -> Bool {
        process(timestamp: timestamp) {
            try SensorKit.FetchResult(sample: object, timestamp: timestamp, sourceDevice: sourceDevice, for: sensor)
        }
    }

    private func process(
        timestamp: SRAbsoluteTime,
        fetchResult: () throws -> SensorKit.FetchResult<Sample>
    ) -> Bool {
        processResult {
            let fetchResult = try fetchResult()
            let clock = lock.withLock { nativeClock }
            let newSamples = SensorKit.FetchResultsIterator(fetchResult).map {
                (timestamp: clock?.date(for: timestamp.rawValue) ?? $0,
                 sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
            }
            guard Sample.self == SRElectrocardiogramSample.self else {
                let samples = try Sample.processIntoSafeRepresentation(newSamples)
                try add(samples, at: timestamp, sourceDevice: fetchResult.sourceDevice, containsNativeSamples: !newSamples.isEmpty)
                return
            }
            guard let native = newSamples as? [(timestamp: Date, sample: SRElectrocardiogramSample)] else {
                throw SensorKitECGSession.ProcessingError.inconsistentSession
            }
            let groups = SRElectrocardiogramSample.inputGroups(native)
            try process(receivedECGResult(groups, at: timestamp, sourceDevice: fetchResult.sourceDevice))
        }
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
            do {
                try finishPendingECGSessions()
            } catch {
                lock.unlock()
                fail(error)
                return
            }
            recordBatchEnd()
            // The end of the fetch confirms the last batch end.
            if let candidateBatchEnd {
                confirm(candidateBatchEnd)
            }
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


@available(iOS 18, *)
extension FetchDelegate {
    fileprivate func processECGGroups(
        _ groups: [SensorKitECGSession.InputGroup],
        timestamp: SRAbsoluteTime,
        sourceDevice: SensorKit.SourceDeviceInfo?
    ) -> Bool {
        processResult {
            try process(receivedECGResult(groups, at: timestamp, sourceDevice: sourceDevice))
        }
    }

    private func receivedECGResult(
        _ groups: [SensorKitECGSession.InputGroup], at timestamp: SRAbsoluteTime, sourceDevice: SensorKit.SourceDeviceInfo?
    ) -> ECGResult {
        lock.withLock {
            defer {
                receivedECGResultCount += 1
            }
            return ECGResult(groups: groups, timestamp: timestamp, sourceDevice: sourceDevice, number: receivedECGResultCount)
        }
    }

    /// Processes one native result, failing the fetch when `body` throws.
    ///
    /// - Returns: Whether the fetch continues.
    private func processResult(_ body: () throws -> Void) -> Bool {
        guard lock.withLock({ state.isFetching }) else {
            return false
        }
        do {
            try body()
        } catch {
            logger.error("SensorKit batch processing failed; error type: \(String(reflecting: type(of: error)), privacy: .public)")
            // Advancing past a malformed native result would make a later acknowledged batch
            // permanently skip it. Terminate and surface the error while the persisted cursor stays.
            fail(error)
            return false
        }
        return lock.withLock { state.isFetching }
    }

    /// Resets the collected state to that of a fetch that starts at `boundary`.
    ///
    /// The caller must hold `lock`.
    private func startOver(at boundary: SRAbsoluteTime) {
        resultsAfterBatchEnd = []
        samples.removeAll(keepingCapacity: true)
        boundaryTimestamp = nil
        batchEnd = nil
        candidateBatchEnd = nil
        sourceDevices = SourceDevices()
        trailingSourceDevices = SourceDevices()
        lastSeenTimestamp = boundary
        ecgAssembly = SensorKitECGAssembly(limits: ecgProcessingLimits)
    }

    /// Confirms the candidate batch end when the result at `timestamp` is later than its boundary, and withdraws it
    /// otherwise, because a fetch from the boundary would not read that result again.
    ///
    /// The caller must hold `lock`.
    private func observe(_ timestamp: SRAbsoluteTime) {
        guard let candidateBatchEnd else {
            return
        }
        if timestamp > candidateBatchEnd.boundary {
            confirm(candidateBatchEnd)
        } else {
            self.candidateBatchEnd = nil
        }
    }

    /// Makes `end` the batch end a delivery takes, and drops the retained ECG results up to its boundary.
    ///
    /// The caller must hold `lock`.
    private func confirm(_ end: BatchEnd) {
        batchEnd = end
        candidateBatchEnd = nil
        resultsAfterBatchEnd.removeAll { $0.timestamp <= end.boundary }
    }

    /// Adds the samples of the result at `timestamp` to the current batch. A full batch is delivered first when the
    /// result is later than its boundary, so the results that share the boundary's timestamp belong to the batch.
    private func add(
        _ newSamples: [Sample.SafeRepresentation],
        at timestamp: SRAbsoluteTime,
        sourceDevice: SensorKit.SourceDeviceInfo?,
        containsNativeSamples: Bool
    ) throws {
        lock.withLock { observe(timestamp) }
        try deliverBatchIfFull()
        lock.withLock {
            collect(newSamples, at: timestamp, sourceDevice: sourceDevice, containsNativeSamples: containsNativeSamples)
        }
    }

    /// Adds the samples of the result at `timestamp` and records the candidate batch end after them.
    ///
    /// The caller must hold `lock`.
    ///
    /// - Parameter addsData: Whether the result moves the boundary. An ECG result that carries no data of a session
    ///   the fetch is assembling, because its groups are all fragments the fetch skips or it has none, doesn't, and
    ///   names no peripheral: whether a later session ends a session before it or the end of the fetch finishes it,
    ///   the session then joins the batch at the same boundary.
    private func collect(
        _ newSamples: [Sample.SafeRepresentation],
        at timestamp: SRAbsoluteTime,
        sourceDevice: SensorKit.SourceDeviceInfo?,
        containsNativeSamples: Bool,
        addsData: Bool = true
    ) {
        // re-check under the lock: a deinit-triggered `stop()` may have interleaved since the
        // caller's check, in which case the batch must be dropped (post-stop, `samples` stays empty).
        guard state.isFetching else {
            return
        }
        guard addsData else {
            recordBatchEnd()
            return
        }
        lastSeenTimestamp = lastSeenTimestamp.map { max($0, timestamp) } ?? timestamp
        if containsNativeSamples {
            trailingSourceDevices.add(sourceDevice)
        }
        append(newSamples)
        recordBatchEnd()
    }

    private func process(_ result: ECGResult) throws {
        guard lock.withLock({ state.isFetching }) else {
            return
        }
        // The unfinished sessions this result carries no data of end before it: they join the batch at the boundary
        // before this result, where the batch may also end.
        let superseded = try lock.withLock {
            observe(result.timestamp)
            let output = ecgAssembly.finishPending(supersededBy: result.groups)
            append(try representations(of: output.sessions))
            recordBatchEnd(before: result.timestamp)
            return output
        }
        logSkippedECGSessions(superseded.skippedSessionCount, atStep: 2 * result.number)
        if try deliverBatchIfFull() {
            // The delivery started over with the retained results, so the result is processed from its start against
            // them. Each round delivers a batch, so this ends.
            try process(result)
            return
        }
        let output: SensorKitECGAssembly.Output
        do {
            output = try lock.withLock { try ecgAssembly.append(result.groups, at: result.timestamp.rawValue) }
        } catch SensorKitECGSession.ProcessingError.assemblyCapacityExceeded {
            guard try releaseECGCapacity() else {
                throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded
            }
            // Making room changed what is retained, so the result is processed from its start. Each round delivers
            // a batch or forgets a session, so this ends.
            try process(result)
            return
        }
        logSkippedECGSessions(output.skippedSessionCount, atStep: 2 * result.number + 1)
        let sessions = try representations(of: output.sessions)
        lock.withLock {
            resultsAfterBatchEnd.append(result)
            collect(
                sessions,
                at: result.timestamp,
                sourceDevice: result.sourceDevice,
                containsNativeSamples: !result.groups.isEmpty,
                addsData: output.addedData
            )
        }
        // A batch end at this result's timestamp waits for a later result. One before it, which this result confirmed
        // by ending the sessions that blocked it, is delivered once full; the delivery processes this retained result
        // again.
        try deliverBatchIfFull()
    }

    /// Makes room for a result that exceeds the ECG limits: delivers the current batch, or, with no samples
    /// collected, forgets the skipped sessions.
    ///
    /// - Returns: Whether there was room to make. Without it, the result doesn't fit the limits together with the
    ///   samples and unfinished sessions that no batch can end before.
    private func releaseECGCapacity() throws -> Bool {
        lock.lock()
        guard !samples.isEmpty else {
            defer {
                lock.unlock()
            }
            return ecgAssembly.forgetFinishedSessions()
        }
        let canDeliver = batchEnd != nil
        lock.unlock()
        if canDeliver {
            try deliverBatch()
        }
        return canDeliver
    }

    /// Finishes the ECG sessions still unfinished when the native fetch completes, unless they are held.
    ///
    /// When the latest result of the unfinished sessions is older than the hold cutoff, they can't receive more
    /// data, so they are finished like sessions that another session followed. Otherwise the end of the fetch may
    /// have cut them off: they are left for the next fetch, which reads them whole from the batch's boundary.
    ///
    /// The caller must hold `lock`.
    private func finishPendingECGSessions() throws {
        guard let pending = ecgAssembly.pendingTimestamps, pending.latest < ecgHoldCutoff else {
            return
        }
        let finished = ecgAssembly.finishPending()
        append(try representations(of: finished.sessions))
        logSkippedECGSessions(finished.skippedSessionCount, atStep: .max)
    }

    private func representations(of sessions: [SensorKitECGSession]) throws -> [Sample.SafeRepresentation] {
        guard let result = sessions as? [Sample.SafeRepresentation] else {
            throw SensorKitECGSession.ProcessingError.inconsistentSession
        }
        return result
    }

    /// Adds samples to the collected ones, whose boundary becomes the largest native timestamp received so far.
    ///
    /// The caller must hold `lock`.
    private func append(_ newSamples: [Sample.SafeRepresentation]) {
        guard state.isFetching, !newSamples.isEmpty else {
            return
        }
        samples.append(contentsOf: newSamples)
        boundaryTimestamp = lastSeenTimestamp
        sourceDevices.formUnion(trailingSourceDevices)
        trailingSourceDevices = SourceDevices()
    }

    /// Records that the current batch can end with the samples collected so far, when a fetch from their boundary
    /// reads again whatever the batch leaves out: every unfinished ECG session started after the boundary and, for a
    /// batch that ends before a result is processed, that result is later than the boundary too. That result, or a
    /// result already received after the boundary, confirms the batch end; a batch end at the latest timestamp is a
    /// candidate.
    ///
    /// The caller must hold `lock`.
    private func recordBatchEnd(before result: SRAbsoluteTime? = nil) {
        guard state.isFetching, !samples.isEmpty, let boundaryTimestamp else {
            // Without samples no batch ends before the results up to the latest one with data, so only later ones,
            // which a fetch from a later boundary reads again, stay retained.
            if let lastSeenTimestamp {
                resultsAfterBatchEnd.removeAll { $0.timestamp <= lastSeenTimestamp }
            }
            return
        }
        guard samples.count > batchEnd?.sampleCount ?? 0 else {
            return
        }
        if let result, result <= boundaryTimestamp {
            return
        }
        if let pending = ecgAssembly.pendingTimestamps, pending.earliest <= boundaryTimestamp.rawValue {
            return
        }
        var devices = sourceDevices
        if lastSeenTimestamp == boundaryTimestamp {
            // The results at the boundary's timestamp belong to the batch, also those without a usable sample.
            devices.formUnion(trailingSourceDevices)
        }
        let end = BatchEnd(sampleCount: samples.count, boundary: boundaryTimestamp, sourceDevices: devices)
        // A result after the boundary confirms the batch end: the one about to be processed, or one already received.
        // Only a batch end at the latest timestamp waits for a later result.
        if result != nil || lastSeenTimestamp.map({ $0 > boundaryTimestamp }) == true {
            confirm(end)
        } else {
            candidateBatchEnd = end
        }
    }

    /// Delivers the current batch once its confirmed batch end holds the batch size.
    ///
    /// - Returns: Whether it delivered a batch.
    @discardableResult
    private func deliverBatchIfFull() throws -> Bool {
        guard lock.withLock({ batchEnd?.sampleCount ?? 0 >= batchSize }) else {
            return false
        }
        try deliverBatch()
        return true
    }

    /// Delivers the current batch and processes the retained results after its boundary again.
    private func deliverBatch() throws {
        for result in processCurrentSamples() {
            try process(result)
        }
    }

    /// The skipped ECG sessions logged in this native fetch, for tests.
    func loggedSkippedECGSessionCount() -> Int {
        lock.withLock { skippedECGSessionLogCount }
    }

    /// Logs the sessions skipped at `step`, unless processing a result again repeats a logged step.
    private func logSkippedECGSessions(_ count: Int, atStep step: Int) {
        let isNew = lock.withLock {
            guard step > lastLoggedECGStep else {
                return false
            }
            lastLoggedECGStep = step
            skippedECGSessionLogCount += count
            return true
        }
        if isNew, count > 0 {
            logger.notice("Skipped \(count, privacy: .public) unusable ECG sessions")
        }
    }
}
