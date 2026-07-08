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
@available(iOS 17, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by #samples.
    final class SampleCountBasedFetcher: AsyncIteratorProtocol {
        private let anchor: ManagedQueryAnchor
        private let reader: SRSensorReader
        nonisolated(unsafe) private let delegate: FetchDelegate<Sample> // swiftlint:disable:this weak_delegate
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
            if !isFetching {
                isFetching = true
                let fetchRequest = SRFetchRequest()
                fetchRequest.device = device
                fetchRequest.from = SRAbsoluteTime(try anchor.value.timestamp)
                fetchRequest.to = .current()
                reader.fetch(fetchRequest)
            }
            return try await delegate.nextBatch()
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
private final class FetchDelegate<Sample: SensorKitSampleProtocol>: NSObject, SRSensorReaderDelegate {
    typealias Element = AnchoredFetcher<Sample>.Element
    
    private let logger: Logger
    private let sensor: Sensor<Sample>
    private let deviceInfo: SensorKit.DeviceInfo
    private let batchSize: Int
    private let anchor: ManagedQueryAnchor
    
    private var isActive = true
    
    private(set) var samples: [Sample.SafeRepresentation] = []
    private(set) var lastSeenTimestamp: SRAbsoluteTime?
    
    // the lock (which protects the `stop` and `processCurrentSamples` functions)
    // is needed to work around a double free which can occur when the owning `SampleCountBasedFetcher`
    // gets deallocated and calls the `stop()` function at the same time as SensorKit is also
    // calling `stop` and/or `processCurrentSamples. (i think.)
    private let lock = NSRecursiveLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var nextBatchContinuation: CheckedContinuation<Element?, any Error>?
    
    init(sensor: Sensor<Sample>, deviceInfo: SensorKit.DeviceInfo, batchSize: Int, anchor: ManagedQueryAnchor) {
        self.logger = Logger(subsystem: "edu.stanford.SpeziSensorKit", category: "\(Self.self)")
        self.sensor = sensor
        self.deviceInfo = deviceInfo
        self.batchSize = batchSize
        self.anchor = anchor
        self.samples.reserveCapacity(batchSize + (batchSize / 5))
    }
    
    func nextBatch() async throws -> Element? {
        guard isActive else {
            return nil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
            precondition(self.isActive)
            precondition(self.nextBatchContinuation == nil, "\(self.sensor.displayName)")
            self.nextBatchContinuation = continuation
            self.semaphore.signal() // signal that continuation is ready
            precondition(self.isActive)
        }
    }
    
    func stop() {
        lock.lock()
        defer {
            lock.unlock()
        }
        isActive = false
        samples.removeAll()
        lastSeenTimestamp = nil
        assert(nextBatchContinuation == nil)
        nextBatchContinuation = nil
        semaphore.signal() // in case the process function is currently waiting on the semaphore...
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
                logger.error("Failed to upadate query anchor: \(error)")
            }
        }
        samples.removeAll(keepingCapacity: true)
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        guard isActive else {
            return false
        }
        do {
            // make sure we properly limit the lifetimes of the on-demand-decoded SRFetchResult sample properties...
            try autoreleasepool {
                let fetchResult = SensorKit.FetchResult(result, for: sensor)
                let samples = SensorKit.FetchResultsIterator(fetchResult).map {
                    (timestamp: $0, sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
                }
                self.samples.append(contentsOf: try Sample.processIntoSafeRepresentation(samples))
                lastSeenTimestamp = lastSeenTimestamp.map { max($0, result.timestamp) } ?? result.timestamp
            }
        } catch {
            logger.error("Error processing fetch result: \(error)")
            // we simply skip this result and continue normally
            return true
        }
        if self.samples.count >= batchSize {
            processCurrentSamples()
        }
        return isActive
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, failedWithError error: any Error) {
        isActive = false
        nextBatchContinuation?.resume(throwing: error)
        nextBatchContinuation = nil
        stop()
    }
    
    func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
        isActive = false
        processCurrentSamples()
        stop()
    }
}
