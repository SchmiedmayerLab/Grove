//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit


// MARK: DefaultSensorKitSampleSafeRepresentation

/// A default ``SensorKitSampleSafeRepresentation``, intended for sensors whose types are already `Sendable` and not confined to the SensorKit thread.
@dynamicMemberLookup
public struct DefaultSensorKitSampleSafeRepresentation<Sample: Hashable & Sendable>: SensorKitSampleSafeRepresentation {
    /// The point in time when the system recorded the measurement.
    public let timestamp: Date
    /// The underlying sample.
    public let sample: Sample
    
    @inlinable public var timeRange: Range<Date> {
        timestamp..<timestamp
    }
    
    @inlinable
    init(timestamp: Date, sample: Sample) {
        self.timestamp = timestamp
        self.sample = sample
    }
    
    /// Access a property on the underlying sample.
    @inlinable
    public subscript<T>(dynamicMember keyPath: KeyPath<Sample, T>) -> T {
        sample[keyPath: keyPath]
    }
}

extension DefaultSensorKitSampleSafeRepresentation: Identifiable where Sample: Identifiable {
    @inlinable public var id: Sample.ID {
        sample.id
    }
}


// MARK: SampleType Extensions

@available(iOS 18, macOS 15, watchOS 11, *)
extension SRWristTemperatureSession: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRWristTemperatureSession>
}


@available(iOS 17.4, *)
extension SRPhotoplethysmogramSample: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRPhotoplethysmogramSample>
}
