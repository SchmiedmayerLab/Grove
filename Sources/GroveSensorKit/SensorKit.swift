//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Grove
import GroveFoundation
@_spi(Internal) import GroveLocalStorage
public import Observation
@_documentation(visibility: internal) @_exported public import SensorKit
import SwiftUI


/// Interact with SensorKit in your Grove application
///
/// ## Topics
///
/// ### Initializers
/// - ``init()``
///
/// ### Authorization Handling
/// - ``authorizationStatus(for:)``
/// - ``requestAccess(to:)``
///
/// ## Anchored Querying
/// - ``fetchAnchored(_:acquisitionNamespace:batchSize:initialStartDate:ecgProcessingLimits:)``
/// - ``resetQueryAnchors(for:acquisitionNamespace:)``
/// - ``discardPendingBatches(for:acquisitionNamespace:)``
/// - ``removeQueryAnchors(acquisitionNamespace:)``
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class SensorKit: Module, EnvironmentAccessible, @unchecked Sendable {
    /// Identifies a query anchor.
    public struct QueryAnchorKey: Hashable {
        let sensor: any AnySensor
        // eg `iPhone18,2` or `Watch7,12`
        let deviceProductType: String
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sensor.id == rhs.sensor.id && lhs.deviceProductType == rhs.deviceProductType
        }
        
        public func hash(into hasher: inout Hasher) {
            sensor.hash(into: &hasher)
            hasher.combine(deviceProductType)
        }
    }
    
    /// Identifies the stored query anchor of one sensor and device, either unscoped or in an acquisition namespace.
    struct StoredQueryAnchorKey: Hashable {
        let namespace: UUID?
        let query: QueryAnchorKey

        var storageIdentifier: String {
            "\(Self.storagePrefix(namespace: namespace))\(query.sensor.id).\(query.deviceProductType)"
        }

        /// The prefix of every stored anchor key of `namespace`, or of the unscoped anchors.
        static func storagePrefix(namespace: UUID?) -> String {
            guard let namespace else {
                return "\(SensorKit.queryAnchorKeyPrefix)."
            }
            return "\(SensorKit.queryAnchorKeyPrefix).scoped.\(namespace.uuidString.lowercased())."
        }
    }

    static let queryAnchorKeyPrefix = "SensorKit.queryAnchors"
    
    @ObservationIgnored @Dependency(LocalStorage.self) private var localStorage
    
    private let queryAnchorKeys = LocalStorageKeysStore<StoredQueryAnchorKey, QueryAnchor> { key in
        LocalStorageKey(key.storageIdentifier)
    }
    
    /// Creates a new instance of the `SensorKit` module.
    nonisolated public init() {}
}


// MARK: Authorization

@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// The resulting state of a SensorKit sensor access request.
    public struct AuthorizationResult {
        /// The sensors to which the user has granted access.
        public let authorized: [any AnySensor]
        /// The sensors to which the user has denied access.
        public let denied: [any AnySensor]
        
        init(_ sensors: some Collection<any AnySensor>) {
            authorized = sensors.filter { $0.authorizationStatus == .authorized }
            denied = sensors.filter { $0.authorizationStatus == .denied }
        }
    }
    
    /// Checks the  current authorization status of the specified sensor.
    nonisolated public func authorizationStatus(for sensor: Sensor<some Any>) -> SRAuthorizationStatus {
        SRSensorReader(sensor: sensor.srSensor).authorizationStatus
    }
    
    /// Requests access to read data from the specified ``Sensor``s.
    ///
    /// - Note: It is not possible to re-request access for a sensor after the user has already denied it.
    ///
    /// - Important: This function returning without throwing an error does not mean that the user actuallt granted access to all requested sensors. Always check the return value.
    ///
    /// - parameter sensors: The sensors for which we want to request access.
    /// - returns: A summary which of the `sensors` passed to the function are now authorized and which are denied.
    nonisolated public func requestAccess(to sensors: [any AnySensor]) async throws -> AuthorizationResult {
        guard !sensors.isEmpty else {
            return AuthorizationResult(EmptyCollection())
        }
        try SensorKit.assertIsAvailable()
        let sensorsToActuallyRequest = sensors.compactMapIntoSet {
            $0.authorizationStatus == .notDetermined ? $0.srSensor : nil
        }
        try await SRSensorReader.requestAuthorization(sensors: sensorsToActuallyRequest)
        return AuthorizationResult(sensors)
    }
}


// MARK: Data Exporting

@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// Performs an anchored fetch.
    ///
    /// The SensorKit module keeps track of the last time an anchored fetch was performed for a specific ``Sensor`` and
    /// device; a fetch returns only the samples SensorKit added since the last fetch.
    ///
    /// An acquisition namespace isolates the durable cursors of one caller-owned source. Reuse the namespace when
    /// restoring the same source; fetching another namespace neither resets nor acknowledges this one's pending
    /// batches. The acquisition coordinates of the batches are the same in every namespace.
    ///
    /// - Parameters:
    ///   - sensor: The ``Sensor`` from which data should be fetched.
    ///   - acquisitionNamespace: The namespace of the cursors, or `nil` for the unscoped cursors.
    ///   - batchSize: The batch size of the returned sequence. Omit it to use the `sensor`'s default batch size.
    ///   - initialStartDate: Where an empty cursor starts. It never changes an established cursor.
    ///   - ecgProcessingLimits: For the ECG sensor with a sample-count batch size, the limits within which ECG sessions
    ///     are assembled across native callbacks. Without them, the ECG sensor keeps its time-range cursor.
    ///
    /// - Note: In order to fetch data from a sensor, you first need to request permission and call ``Sensor/startRecording()``
    @available(iOS 18, *)
    public func fetchAnchored<Sample>(
        _ sensor: Sensor<Sample>,
        acquisitionNamespace: UUID? = nil,
        batchSize: BatchSize? = nil,
        initialStartDate: Date? = nil,
        ecgProcessingLimits: SensorKitECGProcessingLimits? = nil
    ) async throws -> some AsyncSequence<SensorKit.AnchoredBatch<Sample.SafeRepresentation>, any Error> {
        try await AnchoredFetcher(
            sensor: sensor,
            batchSize: batchSize,
            initialStartDate: initialStartDate,
            ecgProcessingLimits: ecgProcessingLimits
        ) { query in
            let storageKey = self.queryAnchorKeys.storageKey(for: StoredQueryAnchorKey(namespace: acquisitionNamespace, query: query))
            return ManagedQueryAnchor(storageKey: storageKey, in: self.localStorage)
        }
    }

    /// Returns the internal value of the sensor's query anchor.
    ///
    /// - returns: A dictionary whose keys are device product type strings (e.g., `iPhone18,2` or `Watch7,12`), and whose values are the query anchor values for these devices.
    ///
    /// - Note: This function only returns values for devices for which there currently exists data in SensorKit.
    ///
    /// - Important: This function is intended exclusively for debugging purposes; query anchors' internal representations are an implementation detail and may change without notice.
    @_spi(Internal)
    public func queryAnchorValues(for sensor: any AnySensor) async throws -> [String: Date] {
        let devices = try await sensor.fetchDevices()
        return try devices.reduce(into: [:]) { dict, device in
            dict[device.productType] = try queryAnchorValue(
                for: sensor,
                deviceProductType: device.productType
            )
        }
    }
    
    /// Returns the internal value of the sensor's query anchor.
    ///
    /// - Important: This function is intended exclusively for debugging purposes; query anchors' internal representations are an implementation detail and may change without notice.
    @_spi(Internal)
    public func queryAnchorValue(for sensor: any AnySensor, deviceProductType: String) throws -> Date? {
        let storageKey = queryAnchorKeys.storageKey(for: StoredQueryAnchorKey(
            namespace: nil,
            query: QueryAnchorKey(sensor: sensor, deviceProductType: deviceProductType)
        ))
        return try localStorage.load(storageKey)?.timestamp
    }
    
    /// Resets the query anchors of the specified sensor.
    ///
    /// Subsequent fetches can then return samples again that were already processed. A batch that was delivered but
    /// never acknowledged is abandoned along with the cursor, and the new reset generation gives the samples fetched
    /// afterwards fresh acquisition coordinates.
    ///
    /// - Parameters:
    ///   - sensor: The sensor whose cursors are reset, on every device.
    ///   - acquisitionNamespace: The namespace of the cursors, or `nil` for the unscoped cursors.
    public func resetQueryAnchors(for sensor: any AnySensor, acquisitionNamespace: UUID? = nil) async throws {
        try await forEachQueryAnchor(of: sensor, acquisitionNamespace: acquisitionNamespace) { try $0.reset() }
    }

    /// Abandons every delivered-but-unacknowledged batch of the specified sensor, keeping the committed cursors.
    ///
    /// Use this to recover from ``QueryAnchorAcknowledgementError/pendingBatchMismatch``: SensorKit does not
    /// promise to replay a pending batch exactly, and the fetcher refuses to continue until the pending batch is
    /// resolved. After discarding, the next fetch returns the same range again under a new reset generation, so its
    /// records get fresh acquisition coordinates and never collide with records the consumer may already have
    /// published from the abandoned batch.
    ///
    /// - Parameters:
    ///   - sensor: The sensor whose pending batches are abandoned, on every device.
    ///   - acquisitionNamespace: The namespace of the cursors, or `nil` for the unscoped cursors.
    public func discardPendingBatches(for sensor: any AnySensor, acquisitionNamespace: UUID? = nil) async throws {
        try await forEachQueryAnchor(of: sensor, acquisitionNamespace: acquisitionNamespace) { try $0.discardPendingBatch() }
    }

    /// Removes every stored query anchor of an acquisition namespace, for all sensors and devices.
    ///
    /// Use this once the namespace's source has ended. A fetch that later uses the same namespace starts from empty
    /// cursors and restarts the namespace's acquisition coordinates, so never reuse a removed namespace for a source
    /// whose records were already published.
    public func removeQueryAnchors(acquisitionNamespace: UUID) throws {
        let prefix = StoredQueryAnchorKey.storagePrefix(namespace: acquisitionNamespace)
        let cachedKeys = queryAnchorKeys.allKeys.filter { $0.namespace == acquisitionNamespace }
        for key in cachedKeys {
            try localStorage.delete(queryAnchorKeys.storageKey(for: key))
        }
        let cachedIdentifiers = Set(cachedKeys.map(\.storageIdentifier))
        for rawKey in try localStorage.persistedRawKeys(withPrefix: prefix) where !cachedIdentifiers.contains(rawKey) {
            try localStorage.delete(LocalStorageKey<QueryAnchor>(rawKey))
        }
    }

    private func forEachQueryAnchor(
        of sensor: any AnySensor,
        acquisitionNamespace: UUID?,
        _ body: (ManagedQueryAnchor) throws -> Void
    ) async throws {
        let devices = try await sensor.fetchDevices()
        try SensorKit.validateUniqueDevicePartitions(devices.map(\.productType))
        let rawKeyPrefix = "\(StoredQueryAnchorKey.storagePrefix(namespace: acquisitionNamespace))\(sensor.id)."
        let partitions = Self.devicePartitionsToReset(
            rawKeyPrefix: rawKeyPrefix,
            currentDeviceProductTypes: devices.map(\.productType),
            cachedDeviceProductTypes: queryAnchorKeys.allKeys.lazy
                .filter { $0.namespace == acquisitionNamespace && $0.query.sensor.id == sensor.id }
                .map(\.query.deviceProductType),
            persistedRawKeys: try localStorage.persistedRawKeys(withPrefix: rawKeyPrefix)
        )
        for deviceProductType in partitions.sorted() {
            let key = StoredQueryAnchorKey(
                namespace: acquisitionNamespace,
                query: QueryAnchorKey(sensor: sensor, deviceProductType: deviceProductType)
            )
            try body(ManagedQueryAnchor(storageKey: queryAnchorKeys.storageKey(for: key), in: localStorage))
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// The device partitions of one sensor's cursors: the current devices, the devices of cursors this process uses and
    /// the devices of the persisted cursors whose raw keys start with `rawKeyPrefix`.
    static func devicePartitionsToReset(
        rawKeyPrefix: String,
        currentDeviceProductTypes: [String],
        cachedDeviceProductTypes: some Sequence<String>,
        persistedRawKeys: [String]
    ) -> Set<String> {
        var partitions = Set(currentDeviceProductTypes)
        partitions.formUnion(cachedDeviceProductTypes)
        partitions.formUnion(
            persistedRawKeys.lazy.compactMap { rawKey in
                guard rawKey.hasPrefix(rawKeyPrefix) else {
                    return nil
                }
                let productType = rawKey.dropFirst(rawKeyPrefix.count)
                return productType.isEmpty ? nil : String(productType)
            }
        )
        return partitions
    }
}


// MARK: Other

@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// An (intentionally not public) wrapper error type to give errors originating from SensorKit more useful error messages.
    enum SensorKitError: LocalizedError {
        /// An operation on the sensor failed because the user has denied the app authorization to access the sensor.
        case deniedAuthorization(any AnySensor)
        /// Some other, unknown error has happened.
        case other(any Error)
        
        var errorDescription: String? {
            switch self {
            case .deniedAuthorization(let sensor):
                String(localized: "The operation failed because the user has denied access to the \(sensor.displayName) sensor.")
            case .other(let error):
                (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        
        var failureReason: String? {
            switch self {
            case .deniedAuthorization:
                nil
            case .other(let error):
                (error as? any LocalizedError)?.failureReason
            }
        }
        
        var helpAnchor: String? {
            switch self {
            case .deniedAuthorization:
                nil
            case .other(let error):
                (error as? any LocalizedError)?.helpAnchor
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .deniedAuthorization:
                nil
            case .other(let error):
                (error as? any LocalizedError)?.recoverySuggestion
            }
        }
        
        init(_ error: any Error, sensor: any AnySensor) {
            if sensor.authorizationStatus == .denied {
                // in some cases (eg: startRecording()), SensorKit will actually set a proper
                // errorCode 1 (no authorization) when attempting to operate on a denied sensor,
                // but in some other cases (eg: fetchDevices()) it does not.
                // so to make things a little easier, we simply assume that any errors raised on sensors
                // for which the user has denied access are happening because the user denied access.
                self = .deniedAuthorization(sensor)
            } else {
                self = .other(error)
            }
        }
    }
}
