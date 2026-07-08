//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation
public import SensorKit


// MARK: DefaultSensorKitSampleSafeRepresentation

/// A default ``SensorKitSampleSafeRepresentation``, intended for sensors whose types are already `Sendable` and not confined to the SensorKit thread.
@dynamicMemberLookup
@available(iOS 17, *)
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

@available(iOS 17, *)
extension DefaultSensorKitSampleSafeRepresentation: Identifiable where Sample: Identifiable {
    @inlinable public var id: Sample.ID {
        sample.id
    }
}


// MARK: SampleType Extensions

@available(iOS 17, *)
extension SRWristTemperatureSession: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRWristTemperatureSession>
}


@available(iOS 17.4, *)
@available(iOS 17, *)
extension SRPhotoplethysmogramSample: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRPhotoplethysmogramSample>
}


@available(iOS 17, *)
extension SRSpeechMetrics: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRSpeechMetrics>
}


@available(iOS 17, *)
extension SRMediaEvent: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRMediaEvent>
}


@available(iOS 17, *)
extension SRFaceMetrics: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<SRFaceMetrics>
}


@available(iOS 17, *)
extension CMOdometerData: SensorKitSampleProtocol {
    public typealias SafeRepresentation = DefaultSensorKitSampleSafeRepresentation<CMOdometerData>
}
