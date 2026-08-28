//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation
private import GroveFoundation
private import OSLog
import SensorKit


@available(iOS 18, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by time interval.
    struct TimeIntervalBasedFetcher: AsyncIteratorProtocol {
        typealias FetchOperation = @Sendable (
            Sensor<Sample>,
            SRDevice,
            Range<Date>
        ) async throws -> [Sample.SafeRepresentation]

        private enum State {
            /// The fetcher hasn't run at all yet.
            case initial
            /// The next `next()` call should fetch and return samples for `timeRange`
            case process(timeRange: Range<Date>, expectedAnchor: QueryAnchor)
            /// A non-empty batch has been yielded and must be acknowledged before another batch is requested.
            case awaitingAcknowledgement(timeRange: Range<Date>, expectedAnchor: QueryAnchor)
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
        private let fetchOperation: FetchOperation
        private var state: State = .initial
        
        init(
            sensor: Sensor<Sample>,
            anchor: ManagedQueryAnchor,
            quarantineCutoff: Date,
            batchSize: TimeInterval,
            device: SRDevice,
            fetchOperation: @escaping FetchOperation = { sensor, device, timeRange in
                try await sensor.fetch(from: device, timeRange: timeRange)
            }
        ) {
            self.sensor = sensor
            self.anchor = anchor
            self.quarantineCutoff = quarantineCutoff
            self.batchSize = Swift::max(batchSize, Self.minAllowedBatchSize)
            self.device = device
            self.fetchOperation = fetchOperation
            if self.batchSize <= 0 || !self.batchSize.isNormal {
                state = .done
                let logger = Logger(subsystem: "org.grovealliance", category: "GroveSensorKit")
                logger.error("Created \(Self.self) with invalid batch size. This is not allowed. The fetcher will never return any results.")
            }
        }
        
        private mutating func prepareInitialState() throws {
            switch state {
            case .done:
                return
            case .initial:
                var currentAnchor = try anchor.value
                if let pendingBatch = currentAnchor.pendingBatch {
                    guard pendingBatch.mode == .timeRange,
                          pendingBatch.sampleCount > 0,
                          let pendingRange = pendingBatch.timeRange else {
                        throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                    }
                    state = .process(timeRange: pendingRange, expectedAnchor: currentAnchor)
                    return
                }
                guard currentAnchor.timestamp < quarantineCutoff else {
                    state = .done
                    return
                }
                if currentAnchor.timestamp == .distantPast {
                    // first time
                    let initialAnchor = currentAnchor.advancedPastEmptyRange(
                        to: quarantineCutoff.addingTimeInterval(-Duration.days(7).timeInterval)
                    )
                    guard try anchor.update(from: currentAnchor, to: initialAnchor) else {
                        throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                    }
                    currentAnchor = initialAnchor
                }
                let batchStartDate = currentAnchor.timestamp
                let batchEndDate = Swift.min(batchStartDate.addingTimeInterval(batchSize), quarantineCutoff)
                state = .process(timeRange: batchStartDate..<batchEndDate, expectedAnchor: currentAnchor)
            case .process, .awaitingAcknowledgement:
                return
            }
        }

        private mutating func commitAndAdvance(_ timeRange: Range<Date>, expectedAnchor: QueryAnchor) throws {
            guard expectedAnchor.pendingBatch == nil else {
                throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
            }
            let desiredAnchor = expectedAnchor.advancedPastEmptyRange(to: timeRange.upperBound)
            guard try anchor.update(from: expectedAnchor, to: desiredAnchor) else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
            advanceAfterCommit(timeRange, committedAnchor: desiredAnchor)
        }

        private mutating func advanceAfterCommit(_ timeRange: Range<Date>, committedAnchor: QueryAnchor) {
            guard timeRange.upperBound < quarantineCutoff else {
                state = .done
                return
            }
            let newStartDate = timeRange.upperBound
            let newEndDate = Swift.min(newStartDate.addingTimeInterval(batchSize), quarantineCutoff)
            state = .process(timeRange: newStartDate..<newEndDate, expectedAnchor: committedAnchor)
        }
        
        mutating func next(isolation: isolated (any Actor)?) async throws(Failure) -> Element? {
            switch state {
            case .done:
                return nil
            case .initial:
                try prepareInitialState()
                return try await fetchNextBatch(isolation: isolation)
            case .process:
                return try await fetchNextBatch(isolation: isolation)
            case let .awaitingAcknowledgement(timeRange, expectedAnchor):
                let committedAnchor = try expectedAnchor.committingPendingBatch()
                guard try anchor.value == committedAnchor else {
                    throw SensorKit.QueryAnchorAcknowledgementError.outstandingBatch
                }
                advanceAfterCommit(timeRange, committedAnchor: committedAnchor)
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
        private mutating func fetchNextBatch(isolation _: isolated (any Actor)?) async throws(Failure) -> Element? {
            let device = device
            // SAFETY:
            // this loop will terminate eventually:
            // - if SensorKit returns at least one sample for the time range we're processing (i.e., the batch is not empty)
            // - if we advance forward sufficiently far, so that the fetcher's next time range is within the sensor's quarantine period
            while true {
                guard !Task.isCancelled else {
                    state = .done
                    return nil
                }
                switch state {
                case let .process(timeRange, expectedAnchor):
                    let results = try await fetchOperation(sensor, device, timeRange)
                    if !results.isEmpty {
                        return try prepareAnchoredBatch(
                            results,
                            timeRange: timeRange,
                            expectedAnchor: expectedAnchor,
                            device: device
                        )
                    } else {
                        guard expectedAnchor.pendingBatch == nil else {
                            throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                        }
                        // the batch is empty, i.e. there were no samples for the time range.
                        // the easy way here would be to simply not have the loop and instead
                        // just `return try await next(isolation: isolation)`, but since we
                        // don't know how small the batch size is, and how many empty batches there might be,
                        // we don't want to have the risk of potentially effectively unbounded recursion,
                        // so we instead implement it as a loop
                        try commitAndAdvance(timeRange, expectedAnchor: expectedAnchor)
                        continue
                    }
                case .done, .initial, .awaitingAcknowledgement:
                    // initial is unreachable here, so we simply group it in with done
                    return nil
                }
            }
        }

        private mutating func prepareAnchoredBatch(
            _ results: [Sample.SafeRepresentation],
            timeRange: Range<Date>,
            expectedAnchor: QueryAnchor,
            device: SRDevice
        ) throws -> Element {
            let pendingBatch = QueryAnchor.PendingBatch.timeRange(timeRange, sampleCount: results.count)
            let pendingAnchor: QueryAnchor
            if let persistedPending = expectedAnchor.pendingBatch {
                guard persistedPending == pendingBatch else {
                    throw SensorKit.QueryAnchorAcknowledgementError.pendingBatchMismatch
                }
                pendingAnchor = expectedAnchor
            } else {
                pendingAnchor = expectedAnchor.preparing(pendingBatch)
                guard try anchor.update(from: expectedAnchor, to: pendingAnchor) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
            }
            let committedAnchor = try pendingAnchor.committingPendingBatch()
            state = .awaitingAcknowledgement(timeRange: timeRange, expectedAnchor: pendingAnchor)
            let batchInfo = SensorKit.BatchInfo(
                timeRange: timeRange,
                device: SensorKit.DeviceInfo(device),
                acquisitionBatch: expectedAnchor.acquisitionBatchCoordinate
            )
            let anchor = self.anchor
            let acknowledgement = SensorKit.QueryAnchorAcknowledgement {
                guard try anchor.update(from: pendingAnchor, to: committedAnchor) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
            }
            return SensorKit.AnchoredBatch(info: batchInfo, samples: results, acknowledgement: acknowledgement)
        }
    }
}
