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
@available(iOS 17, *)
extension AnchoredFetcher {
    /// Async iterator that fetches samples batched by time interval.
    struct TimeIntervalBasedFetcher: AsyncIteratorProtocol {
        private enum State {
            case initial
            case process(timeRange: Range<Date>)
            /// The data fetcher is done, i.e. has fetched (and returned) all data that is currently available.
            case done
        }
        
        private let sensor: Sensor<Sample>
        private let anchor: ManagedQueryAnchor
        private let quarantineCutoff: Date
        private let batchSize: TimeInterval
        nonisolated(unsafe) private let device: SRDevice
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
            self.batchSize = batchSize
            self.device = device
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
                return try await next(isolation: isolation)
            case .process(let timeRange):
                let results = try await sensor.fetch(from: device, timeRange: timeRange)
                try advanceState()
                let batchInfo = SensorKit.BatchInfo(timeRange: timeRange, device: SensorKit.DeviceInfo(device))
                return (batchInfo, results)
            }
        }
    }
}
