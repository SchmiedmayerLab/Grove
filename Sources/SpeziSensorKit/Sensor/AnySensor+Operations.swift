//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

private import OSLog
public import SensorKit
public import SpeziFoundation


/// Controls how samples should be batched when performing an anchored fetch.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum BatchSize: Hashable, Sendable {
    /// Each batch should contain `numSamples` samples.
    ///
    /// - Note: When using the ``AnchoredFetcher`` to fetch batches of samples, individual batches might be slightly larger than the limit defined here.
    case numberOfSamples(_ numSamples: Int)
    
    /// Each batch should contain the samples from a time period of length `duration`.
    case timeInterval(_ duration: Duration)
    
    @inlinable internal static var `default`: Self {
        .numberOfSamples(100_000)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnySensor {
    /// The sensor's current authorization status.
    @inlinable public var authorizationStatus: SRAuthorizationStatus {
        SRSensorReader(self).authorizationStatus
    }
    
    /// Tells SensorKit to start data collection for this sensor.
    public func startRecording() async throws {
        let reader = SRSensorReader(self)
        let delegate = StartStopRecordingDelegate(sensor: self)
        reader.delegate = delegate
        // SRSensorReader.delegate is weak; keep the delegate (and reader) alive until the
        // XPC round-trip has resumed the continuation, otherwise the callback may be dropped
        // and the continuation leaked.
        // (same for all other similar functions in this file.)
        defer {
            withExtendedLifetime((reader, delegate)) {}
        }
        try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            reader.startRecording()
        }
    }
    
    /// Tells SensorKit to stop data collection for this sensor.
    public func stopRecording() async throws {
        let reader = SRSensorReader(self)
        let delegate = StartStopRecordingDelegate(sensor: self)
        reader.delegate = delegate
        // see `startRecording()` re delegate/reader lifetimes.
        defer {
            withExtendedLifetime((reader, delegate)) {}
        }
        try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            reader.stopRecording()
        }
    }
    
    /// Fetches a list of all devices that collect data for this sensor.
    public func fetchDevices() async throws -> sending [SRDevice] {
        let reader = SRSensorReader(self)
        let delegate = DevicesFetcherDelegate(sensor: self)
        reader.delegate = delegate
        // see `startRecording()` re delegate/reader lifetimes.
        defer {
            withExtendedLifetime((reader, delegate)) {}
        }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            reader.fetchDevices()
        }
    }
    
    /// Fetches data from SensorKit.
    ///
    /// - parameter device: The `SRDevice` whose data should be queried. Use ``fetchDevices()`` to obtain the list of devices for which the sensor currently has data.
    /// - parameter timeRange: The time range for which data should be queried. Note that if this overlaps with the sensor's quarantine period, it may get clamped.
    /// - returns: The sensor's samples, processed into their ``SensorKitSampleSafeRepresentation``s.
    public func fetch(from device: SRDevice, timeRange: Range<Date>) async throws -> [Sample.SafeRepresentation] {
        let reader = SRSensorReader(self)
        let delegate = SamplesFetcherDelegate(self)
        // see `startRecording()` re delegate/reader lifetimes.
        defer {
            withExtendedLifetime((reader, delegate)) {}
        }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            reader.delegate = delegate
            let fetchRequest = SRFetchRequest()
            fetchRequest.device = device
            fetchRequest.from = .fromCFAbsoluteTime(_cf: timeRange.lowerBound.timeIntervalSinceReferenceDate)
            fetchRequest.to = .fromCFAbsoluteTime(_cf: timeRange.upperBound.timeIntervalSinceReferenceDate)
            reader.fetch(fetchRequest)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnySensor {
    /// Fetches data from SensorKit.
    ///
    /// - parameter device: The `SRDevice` whose data should be queried. Use ``fetchDevices()`` to obtain the list of devices for which the sensor currently has data.
    /// - parameter fetchDuration: The time duration specifying how much data should be fetched, going back from the sensor's current quarantine begin.
    ///     E.g.: if fetch data from a sensor with a 24 hour quarantine period, and specify `.hours(12)` for the fetch duration, this function will fetch data in the time range `now-36h` to `now-24h`.
    /// - returns: The sensor's samples, processed into their ``SensorKitSampleSafeRepresentation``s.
    @inlinable
    public func fetch(from device: SRDevice, mostRecentAvailable fetchDuration: Duration) async throws -> [Sample.SafeRepresentation] {
        let endDate = self.currentQuarantineBegin
        let startDate = endDate.addingTimeInterval(-fetchDuration.timeInterval)
        return try await fetch(from: device, timeRange: startDate..<endDate)
    }
}


// MARK: SRSensorReader Delegates

@available(iOS 18, macOS 15, watchOS 11, *)
private final class StartStopRecordingDelegate: NSObject, SRSensorReaderDelegate {
    let sensor: any AnySensor
    var continuation: CheckedContinuation<Void, any Error>?
    
    init(sensor: any AnySensor) {
        self.sensor = sensor
    }
    
    func sensorReaderWillStartRecording(_ reader: SRSensorReader) {
        continuation?.resume()
        continuation = nil
    }
    
    func sensorReaderDidStopRecording(_ reader: SRSensorReader) {
        continuation?.resume()
        continuation = nil
    }
    
    func sensorReader(_ reader: SRSensorReader, startRecordingFailedWithError error: any Error) {
        continuation?.resume(throwing: SensorKit.SensorKitError(error, sensor: sensor))
        continuation = nil
    }
    
    func sensorReader(_ reader: SRSensorReader, stopRecordingFailedWithError error: any Error) {
        continuation?.resume(throwing: SensorKit.SensorKitError(error, sensor: sensor))
        continuation = nil
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private final class DevicesFetcherDelegate: NSObject, SRSensorReaderDelegate {
    let sensor: any AnySensor
    var continuation: CheckedContinuation<[SRDevice], any Error>?
    
    init(sensor: any AnySensor) {
        self.sensor = sensor
    }
    
    func sensorReader(_ reader: SRSensorReader, didFetch devices: [SRDevice]) {
        nonisolated(unsafe) let devices = devices
        continuation?.resume(returning: devices)
        continuation = nil
    }
    
    func sensorReader(_ reader: SRSensorReader, fetchDevicesDidFailWithError error: any Error) {
        continuation?.resume(throwing: SensorKit.SensorKitError(error, sensor: sensor))
        continuation = nil
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private final class SamplesFetcherDelegate<Sample: SensorKitSampleProtocol>: NSObject, SRSensorReaderDelegate {
    private let logger = Logger(subsystem: "edu.stanford.SpeziSensorKit", category: "SamplesFetcherDelegate")
    private let sensor: Sensor<Sample>
    var continuation: CheckedContinuation<[Sample.SafeRepresentation], any Error>?
    private var results: [SensorKit.FetchResult<Sample>] = []
    
    init(_ sensor: some AnySensor<Sample>) {
        self.sensor = Sensor(sensor)
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
        // The docs say that "If the caller needs to access the result at a later time, it must be copied not merely retained".
        guard let result = result.copy() as? SRFetchResult<AnyObject> else {
            // should be unreachable
            return true
        }
        do {
            let fetchResult = try SensorKit.FetchResult(result, for: self.sensor)
            self.results.append(fetchResult)
        } catch {
            // SensorKit returned something we can't interpret; skip this batch rather than crash.
            logger.error("Error processing fetch result: \(error)")
        }
        return true
    }
    
    func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, failedWithError error: any Error) {
        continuation?.resume(throwing: error)
        results = []
        continuation = nil
    }
    
    func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
        guard let continuation else {
            self.results = []
            return
        }
        nonisolated(unsafe) let results = results
        autoreleasepool {
            let samples = SensorKit.FetchResultsIterator(results).lazy.map {
                (timestamp: $0, sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
            }
            do {
                let processedResults: [Sample.SafeRepresentation] = try Sample.processIntoSafeRepresentation(samples)
                continuation.resume(returning: processedResults)
            } catch {
                continuation.resume(throwing: error)
            }
            self.results = []
            self.continuation = nil
        }
    }
}
