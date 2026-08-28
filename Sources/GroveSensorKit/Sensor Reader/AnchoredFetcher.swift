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
private import Synchronization


@available(iOS 18, *)
enum SampleCountFetchState {
    case fetching
    case flushing
    case failed(any Error)
    case terminated

    var isFetching: Bool {
        switch self {
        case .fetching:
            true
        case .flushing, .failed, .terminated:
            false
        }
    }

    func isValidSuccessor(to previous: Self) -> Bool {
        switch (previous, self) {
        case (.fetching, .fetching), (.flushing, .flushing), (.failed, .failed), (.terminated, .terminated):
            true
        case (.fetching, _):
            true
        case (.flushing, .failed), (.flushing, .terminated):
            true
        case (.flushing, .fetching):
            false
        case (.failed, .terminated):
            true
        case (.failed, .fetching), (.failed, .flushing):
            false
        case (.terminated, .fetching), (.terminated, .flushing), (.terminated, .failed):
            false
        }
    }
}


@available(iOS 18, *)
struct SampleCountRawElement<Sample: SensorKitSampleProtocol> {
    let timeRange: Range<Date>
    let device: SensorKit.DeviceInfo
    let samples: [Sample.SafeRepresentation]
}


/// An `AsyncSequence` that can be used to fetch and process data from SensorKit, split into distinct batches.
///
/// Each batch will be fetched from SensorKit on demand, i.e. when the iterator's `next(isolation:)` function is called.
///
/// - Important: Due to the lazy nature of this type, and the fact that it uses a query anchor internally to keep track of already-fetched time ranges, the sequence should only be iterated once.
@available(iOS 18, *)
public struct AnchoredFetcher<Sample: SensorKitSampleProtocol>: AsyncSequence {
    public typealias Element = SensorKit.AnchoredBatch<Sample.SafeRepresentation>
    public typealias Failure = any Error
    
    private let sensor: Sensor<Sample>
    private let queryAnchorProvider: (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor
    private let batchSize: BatchSize
    private let devices: [SRDevice]
    
    public init(
        sensor: some AnySensor<Sample>,
        batchSize: BatchSize? = nil,
        queryAnchorProvider: @escaping (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor
    ) async throws {
        self.sensor = Sensor(sensor)
        self.queryAnchorProvider = queryAnchorProvider
        self.batchSize = batchSize ?? sensor.suggestedBatchSize
        let devices = try await sensor.fetchDevices()
        try SensorKit.validateUniqueDevicePartitions(devices.map(\.productType))
        self.devices = devices
    }
    
    @_AsyncIteratorBuilder<Element, Failure>
    public consuming func makeAsyncIterator() -> some AsyncIteratorProtocol<Element, Failure> {
        if sensor.id == Sensor.ecg.id {
            // we need to fetch all ECGs at once, since each recording will consist of a series of
            // separate `SRElectrocardiogramSample` objects, and we can't risk accidentally
            // splitting in the middle of that, since we then would not be able to correctly post-process
            // these samples into SensorKitECGSession objects.
            timeIntervalBasedIterator(batchDuration: Duration(secondsComponent: .max, attosecondsComponent: 0))
        } else {
            switch batchSize {
            case .numberOfSamples(let limit):
                for device in devices {
                    let device = device
                    SampleCountBasedFetcher(
                        sensor: sensor,
                        batchSize: limit,
                        anchor: queryAnchorProvider(SensorKit.QueryAnchorKey(sensor: sensor, deviceProductType: device.productType)),
                        device: device
                    )
                }
            case .timeInterval(let duration):
                timeIntervalBasedIterator(batchDuration: duration)
            }
        }
    }
    
    @_AsyncIteratorBuilder<Element, Failure>
    private func timeIntervalBasedIterator(batchDuration duration: Duration) -> some AsyncIteratorProtocol<Element, Failure> {
        for device in devices {
            let device = device
            TimeIntervalBasedFetcher(
                sensor: sensor,
                anchor: queryAnchorProvider(SensorKit.QueryAnchorKey(sensor: sensor, deviceProductType: device.productType)),
                quarantineCutoff: sensor.currentQuarantineBegin,
                batchSize: duration.timeInterval,
                device: device
            )
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// Fail-closed acquisition errors raised before any query cursor is read or advanced.
    public enum AnchoredFetchError: Error, Equatable, Sendable {
        /// SensorKit exposed multiple physical devices under the same only-available stable partition.
        /// Querying them would share a cursor and could silently skip or conflate records.
        case ambiguousDevicePartition(productType: String)
    }

    static func validateUniqueDevicePartitions(_ productTypes: [String]) throws {
        var seen: Set<String> = []
        for productType in productTypes where !seen.insert(productType).inserted {
            throw AnchoredFetchError.ambiguousDevicePartition(productType: productType)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// A SensorKit batch whose query cursor advances only after the consumer durably accepts the batch.
    ///
    /// Call ``acknowledge()`` only after all state needed to retry publication has been durably persisted.
    /// Until then, a restart will reissue the persisted delivery boundary. SensorKit may change
    /// records within that boundary, so identity-bearing consumers must verify retry content.
    /// A batch may be acknowledged exactly once.
    public struct AnchoredBatch<Sample: Sendable>: Sendable {
        public let info: BatchInfo
        public let samples: [Sample]
        private let acknowledgement: QueryAnchorAcknowledgement

        init(info: BatchInfo, samples: [Sample], acknowledgement: QueryAnchorAcknowledgement) {
            self.info = info
            self.samples = samples
            self.acknowledgement = acknowledgement
        }

        /// Atomically advances the persisted query cursor for this batch.
        public func acknowledge() async throws {
            try acknowledgement.acknowledge()
        }
    }

    /// Errors raised when acknowledging an anchored SensorKit batch.
    public enum QueryAnchorAcknowledgementError: Error, Equatable, Sendable {
        /// The same batch token was already acknowledged.
        case alreadyAcknowledged
        /// The persisted cursor no longer matches the cursor from which this batch was fetched.
        case staleCursor
        /// The consumer requested another batch before acknowledging the outstanding one.
        case outstandingBatch
        /// Reset was requested while a delivered batch still awaits durable acknowledgement.
        case unresolvedPendingBatch
        /// The persisted cursor has exhausted its reset-generation space.
        case exhaustedResetGeneration
        /// The cursor cannot assign another acquisition-batch sequence in this reset generation.
        case exhaustedBatchSequence
        /// A crash retry did not reproduce the persisted delivery boundary.
        case pendingBatchMismatch
        /// SensorKit delivered source records without the cursor needed to acknowledge them durably.
        case missingDeliveryAnchor
    }

    final class QueryAnchorAcknowledgement: Sendable {
        private enum State: Sendable {
            case pending
            case acknowledged
        }

        private let state = Mutex(State.pending)
        private let operation: @Sendable () throws -> Void

        init(operation: @escaping @Sendable () throws -> Void) {
            self.operation = operation
        }

        func acknowledge() throws {
            try state.withLock { state in
                guard case .pending = state else {
                    throw QueryAnchorAcknowledgementError.alreadyAcknowledged
                }
                try operation()
                state = .acknowledged
            }
        }
    }

    /// Info about a device from which sensor data was collected.
    ///
    /// - Note: Since the same `DeviceInfo` instance is associated with many samples, and might be passed around a lot in code,
    ///     this is a class rather than a struct, in order to reduce the required amount of copying.
    public final class DeviceInfo: CustomStringConvertible, Sendable {
        /// The user-defined name of the device.
        public let model: String
        /// The framework-defined name of the device.
        public let name: String
        /// The device’s operating system.
        public let systemName: String
        /// The device’s operating system version.
        public let systemVersion: String
        /// A string that identifies the device used to save a sample.
        public let productType: String
        
        public var description: String {
            "model=\(model); name=\(name); systemName=\(systemName); systemVersion=\(systemVersion); productType=\(productType)"
        }
        
        /// Creates a new `DeviceInfo` from an `SRDevice`.
        @inlinable
        public init(_ device: borrowing SRDevice) {
            model = device.model
            name = device.name
            systemName = device.systemName
            systemVersion = device.systemVersion
            productType = device.productType
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit.DeviceInfo: Hashable {
    public static func == (lhs: SensorKit.DeviceInfo, rhs: SensorKit.DeviceInfo) -> Bool {
        if ObjectIdentifier(lhs) == ObjectIdentifier(rhs) {
            return true
        } else {
            return lhs.model == rhs.model
                && lhs.name == rhs.name
                && lhs.systemName == rhs.systemName
                && lhs.systemVersion == rhs.systemVersion
                && lhs.productType == rhs.productType
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(model)
        hasher.combine(name)
        hasher.combine(systemName)
        hasher.combine(systemVersion)
        hasher.combine(productType)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// Durable, non-clinical coordinate for one batch delivered by an anchored fetch.
    ///
    /// The coordinate is derived from the persisted cursor before conversion. It is stable across
    /// crash retries, changes when the cursor is reset, and advances even when two consecutive
    /// batches share a SensorKit timestamp. It intentionally contains no measured value.
    public struct AcquisitionBatchCoordinate: Hashable, Codable, Sendable {
        public let cursorTimestamp: Date
        public let resetGeneration: UInt64
        public let sequence: UInt64

        /// Canonical local-ledger representation suitable for a length-delimited identity preimage.
        public var stableValue: String {
            "sensorkit-batch-v1:\(cursorTimestamp.timeIntervalSinceReferenceDate.bitPattern):"
                + "\(resetGeneration):\(sequence)"
        }

        @inlinable
        public init(cursorTimestamp: Date, resetGeneration: UInt64, sequence: UInt64) {
            self.cursorTimestamp = cursorTimestamp
            self.resetGeneration = resetGeneration
            self.sequence = sequence
        }
    }

    public struct BatchInfo: Sendable {
        /// The time range queried for when SensorKit returned this batch's samples.
        public let timeRange: Range<Date>
        /// The source device queried for when SensorKit returned this batch's samples.
        public let device: DeviceInfo
        /// Durable acquisition coordinate allocated before this batch is exposed to its consumer.
        public let acquisitionBatch: AcquisitionBatchCoordinate
        
        @inlinable
        public init(
            timeRange: Range<Date>,
            device: DeviceInfo,
            acquisitionBatch: AcquisitionBatchCoordinate
        ) {
            self.timeRange = timeRange
            self.device = device
            self.acquisitionBatch = acquisitionBatch
        }
    }
}
