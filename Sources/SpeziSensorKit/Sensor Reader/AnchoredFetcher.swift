//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
private import OSLog
import SensorKit
private import SpeziFoundation


/// An `AsyncSequence` that can be used to fetch and process data from SensorKit, split into distinct batches.
///
/// Each batch will be fetched from SensorKit on demand, i.e. when the iterator's `next(isolation:)` function is called.
///
/// - Important: Due to the lazy nature of this type, and the fact that it uses a query anchor internally to keep track of already-fetched time ranges, the sequence should only be iterated once.
@available(iOS 18, *)
public struct AnchoredFetcher<Sample: SensorKitSampleProtocol>: AsyncSequence {
    public typealias Element = (SensorKit.BatchInfo, [Sample.SafeRepresentation])
    public typealias Failure = any Error
    
    private let sensor: Sensor<Sample>
    private let queryAnchorProvider: (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor
    private let batchSize: BatchSize
    private let devices: [SRDevice]
    
    public init(
        sensor: some AnySensor<Sample>,
        queryAnchorProvider: @escaping (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor,
        batchSize: BatchSize? = nil
    ) async throws {
        self.sensor = Sensor(sensor)
        self.queryAnchorProvider = queryAnchorProvider
        self.batchSize = batchSize ?? sensor.suggestedBatchSize
        self.devices = try await sensor.fetchDevices()
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
    public struct BatchInfo: Sendable {
        /// The time range queried for when SensorKit returned this batch's samples.
        public let timeRange: Range<Date>
        /// The source device queried for when SensorKit returned this batch's samples.
        public let device: DeviceInfo
        
        @inlinable
        public init(timeRange: Range<Date>, device: DeviceInfo) {
            self.timeRange = timeRange
            self.device = device
        }
    }
}
