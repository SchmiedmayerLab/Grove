//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
private import OSLog
import SensorKit
private import SpeziFoundation


@available(iOS 18, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by time interval.
    struct TimeIntervalBasedFetcher: AsyncIteratorProtocol {
        private enum State {
            /// The fetcher hasn't run at all yet.
            case initial
            /// The next `next()` call should fetch and return samples for `timeRange`
            case process(timeRange: Range<Date>)
            /// The data fetcher is done, i.e. has fetched (and returned) all data that is currently available.
            case done
        }
        
        /// The minimum allowed batch size; any batch sizes smaller than this value will be "rounded up" to this batch size.
        private static var minAllowedBatchSize: TimeInterval { 0.5 }
        
        private let sensor: Sensor<Sample>
        private let anchor: ManagedQueryAnchor
        private let quarantineCutoff: Date
        private let batchSize: TimeInterval
        private let device: SRDevice
        private var state: State = .initial
        
        init(
            sensor: Sensor<Sample>,
            anchor: ManagedQueryAnchor,
            quarantineCutoff: Date,
            batchSize: TimeInterval,
            device: SRDevice
        ) {
            self.sensor = sensor
            self.anchor = anchor
            self.quarantineCutoff = quarantineCutoff
            self.batchSize = max(batchSize, Self.minAllowedBatchSize)
            self.device = device
            if self.batchSize <= 0 || !self.batchSize.isNormal {
                state = .done
                let logger = Logger(subsystem: "edu.stanford.Spezi", category: "SpeziSensorKit")
                logger.error("Created \(Self.self) with invalid batch size. This is not allowed. The fetcher will never return any results.")
            }
        }
        
        private mutating func advanceState() throws {
            switch state {
            case .done:
                return
            case .initial:
                var currentAnchor = try anchor.value
                guard currentAnchor.timestamp < quarantineCutoff else {
                    state = .done
                    return
                }
                if currentAnchor.timestamp == .distantPast {
                    // first time
                    currentAnchor = .init(timestamp: quarantineCutoff.addingTimeInterval(-Duration.days(7).timeInterval))
                    try anchor.update(currentAnchor)
                }
                let batchStartDate = currentAnchor.timestamp
                let batchEndDate = Swift.min(batchStartDate.addingTimeInterval(batchSize), quarantineCutoff)
                state = .process(timeRange: batchStartDate..<batchEndDate)
            case .process(let timeRange):
                try anchor.update(.init(timestamp: timeRange.upperBound))
                guard timeRange.upperBound < quarantineCutoff else {
                    // we already were processing the last (currently available) batch
                    state = .done
                    return
                }
                let newStartDate = timeRange.upperBound
                let newEndDate = Swift.min(newStartDate.addingTimeInterval(batchSize), quarantineCutoff)
                state = .process(timeRange: newStartDate..<newEndDate)
            }
        }
        
        mutating func next(isolation: isolated (any Actor)?) async throws(Failure) -> Element? {
            switch state {
            case .done:
                return nil
            case .initial:
                try advanceState()
                return try await fetchNextBatch(isolation: isolation)
            case .process:
                return try await fetchNextBatch(isolation: isolation)
            }
        }
        
        /// Explicit witness for the legacy `next()` requirement.
        ///
        /// Needed to work around https://github.com/swiftlang/swift/issues/87849
        /// Can be removed once the deployment target is iOS 18.4+
        mutating func next() async throws(Failure) -> Element? {
            try await next(isolation: nil)
        }
        
        /// Fetches the next non-empty batch, or returns `nil` if there are none.
        ///
        /// This function advances the state as it moves through the fetches.
        private mutating func fetchNextBatch(isolation: isolated (any Actor)?) async throws(Failure) -> Element? {
            nonisolated(unsafe) let device = device
            // SAFETY:
            // this loop will terminate eventually:
            // - if SensorKit returns at least one sample for the time range we're processing (i.e., the batch is not empty)
            // - if we advance forward sufficiently far, so that the fetcher's next time range is within the sensor's quarantine period
            while true {
                switch state {
                case .process(let timeRange):
                    let results = try await sensor.fetch(from: device, timeRange: timeRange)
                    try advanceState()
                    if !results.isEmpty {
                        // the batch is not empty, so we simply return it and that's it.
                        let batchInfo = SensorKit.BatchInfo(timeRange: timeRange, device: SensorKit.DeviceInfo(device))
                        return (batchInfo, results)
                    } else {
                        // the batch is empty, i.e. there were no samples for the time range.
                        // the easy way here would be to simply not have the loop and instead
                        // just `return try await next(isolation: isolation)`, but since we
                        // don't know how small the batch size is, and how many empty batches there might be,
                        // we don't want to have the risk of potentially effectively unbounded recursion,
                        // so we instead implement it as a loop
                        continue
                    }
                case .done, .initial:
                    // initial is unreachable here, so we simply group it in with done
                    return nil
                }
            }
        }
    }
}
