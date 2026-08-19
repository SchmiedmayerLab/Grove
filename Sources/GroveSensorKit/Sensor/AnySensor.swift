//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation
public import SensorKit


/// A type-erased ``Sensor``
///
/// - Important: ``Sensor`` is the only type allowed to conform to ``AnySensor``.
///
/// ## Topics
///
/// ### Associated types
/// - ``Sample``
///
/// ### Instance Properties
/// - ``srSensor``
/// - ``id``
/// - ``displayName``
/// - ``authorizationStatus``
/// - ``dataQuarantineDuration``
/// - ``suggestedBatchSize``
///
/// ### Instance Methods
/// - ``startRecording()``
/// - ``stopRecording()``
/// - ``fetchDevices()``
/// - ``fetch(from:timeRange:)``
/// - ``fetch(from:mostRecentAvailable:)``
///
/// ### Other
/// - ``~=(_:_:)``
/// - ``==(_:_:)-(Sensor<Any>,AnySensor)``
/// - ``==(_:_:)-(AnySensor,Sensor<Any>)``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol AnySensor<Sample>: Hashable, Identifiable, Sendable, CustomStringConvertible {
    /// The type of the sensor's resulting samples.
    associatedtype Sample: SensorKitSampleProtocol
    
    /// The underlying SensorKit `SRSensor`.
    var srSensor: SRSensor { get }
    
    /// The sensor's unique identifier.
    ///
    /// - Important: This value is not guaranteed to be stable, and might vary based on platform and/or OS version.
    var id: String { get }
    
    /// The recommended display name.
    var displayName: String { get }
    
    /// How long the system hold data in quarantine before it can be queried by applications.
    var dataQuarantineDuration: Duration { get }
    
    /// The sensor's suggested batch size.
    var suggestedBatchSize: BatchSize { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnySensor {
    @inlinable public var id: String { // swiftlint:disable:this missing_docs
        srSensor.rawValue
    }
    
    @inlinable var currentQuarantineBegin: Date {
        .now.addingTimeInterval(-dataQuarantineDuration.timeInterval)
    }
}

// MARK: Other

/// Compare two sensors, based on their identifiers
@available(iOS 18, macOS 15, watchOS 11, *)
@inlinable
public func ~= (lhs: Sensor<some Any>, rhs: any AnySensor) -> Bool { // swiftlint:disable:this static_operator
    lhs.id == rhs.id
}

/// Compare two sensors, based on their identifiers
@available(iOS 18, macOS 15, watchOS 11, *)
@inlinable
public func == (lhs: Sensor<some Any>, rhs: any AnySensor) -> Bool { // swiftlint:disable:this static_operator
    lhs.id == rhs.id
}

/// Compare two sensors, based on their identifiers
@available(iOS 18, macOS 15, watchOS 11, *)
@inlinable
public func == (lhs: any AnySensor, rhs: Sensor<some Any>) -> Bool { // swiftlint:disable:this static_operator
    lhs.id == rhs.id
}
