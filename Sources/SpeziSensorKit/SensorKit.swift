//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Observation
@_documentation(visibility: internal) @_exported public import SensorKit
public import Spezi
import SpeziFoundation
import SpeziLocalStorage
import SwiftUI


/// Interact with SensorKit in your Spezi application
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
/// - ``fetchAnchored(_:)``
/// - ``resetQueryAnchor(for:)``
@available(iOS 17, *)
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
    
    static let queryAnchorKeyPrefix = "edu.stanford.SpeziSensorKit.QueryAnchors"
    
    @ObservationIgnored @Dependency(LocalStorage.self) private var localStorage
    
    private let queryAnchorKeys = LocalStorageKeysStore<QueryAnchorKey, QueryAnchor> { key in
        LocalStorageKey("\(SensorKit.queryAnchorKeyPrefix).\(key.sensor.id).\(key.deviceProductType)")
    }
    
    /// Creates a new instance of the `SensorKit` module.
    nonisolated public init() {}
}


// MARK: Authorization

@available(iOS 17, *)
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

@available(iOS 17, *)
extension SensorKit {
    /// Performs an anchored fetch.
    ///
    /// The SensorKit module internally keep track of the last time an anchored fetch was performed for a specific ``Sensor``;
    /// a fetch using this function will return only those samples that have been added to SensorKit since the last fetch for the sensor.
    ///
    /// - parameter sensor: The ``Sensor`` from which data should be fetched
    /// - parameter batchSize: The batch size that should be used by the returned sequence. Omit this to use the `sensor`'s default batch size.
    ///
    /// - Note: In order to fetch data from a sensor, you first need to request permission and call ``Sensor/startRecording()``
    @available(iOS 18, *)
    public func fetchAnchored<Sample>(
        _ sensor: Sensor<Sample>,
        batchSize: BatchSize? = nil
    ) async throws -> some AsyncSequence<(SensorKit.BatchInfo, [Sample.SafeRepresentation]), any Error> {
        try await AnchoredFetcher(sensor: sensor) { queryAnchorKey in
            let storageKey = self.queryAnchorKeys.storageKey(for: queryAnchorKey)
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
        return devices.reduce(into: [:]) { dict, device in
            dict[device.productType] = queryAnchorValue(for: sensor, deviceProductType: device.productType)
        }
    }
    
    /// Returns the internal value of the sensor's query anchor.
    ///
    /// - Important: This function is intended exclusively for debugging purposes; query anchors' internal representations are an implementation detail and may change without notice.
    @_spi(Internal)
    public func queryAnchorValue(for sensor: any AnySensor, deviceProductType: String) -> Date? {
        let storageKey = queryAnchorKeys.storageKey(for: QueryAnchorKey(sensor: sensor, deviceProductType: deviceProductType))
        return (try? localStorage.load(storageKey))?.timestamp
    }
    
    /// Resets the query anchors for the specified sensor.
    ///
    /// This will cause subsequent calls to ``fetchAnchored(_:)`` to potentially re-fetch already-processed samples.
    public func resetQueryAnchors(for sensor: any AnySensor) throws {
        try localStorage.deleteAll { rawKey in
            rawKey.starts(with: "\(SensorKit.queryAnchorKeyPrefix).\(sensor.id)")
        }
    }
    
    /// Resets the query anchors for all sensors.
    public func resetAllQueryAnchors() throws {
        try localStorage.deleteAll { rawKey in
            rawKey.starts(with: SensorKit.queryAnchorKeyPrefix)
        }
    }
}


// MARK: Other

@available(iOS 17, *)
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
