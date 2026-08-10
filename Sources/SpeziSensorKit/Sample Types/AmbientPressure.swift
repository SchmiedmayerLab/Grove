//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


extension CMRecordedPressureData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the system recorded the measurement.
        public let timestamp: Date
        /// A value that uniquely identifies this measurement.
        public let identifier: UInt64
        /// The ambient pressure, in kPa (kilopascals).
        public let pressure: Measurement<UnitPressure>
        /// The ambient temperature, in C (degrees centrigrade).
        public let temperature: Measurement<UnitTemperature>
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(_ data: CMRecordedPressureData) {
            timestamp = data.startDate
            identifier = data.identifier
            pressure = data.pressure
            temperature = data.temperature
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMRecordedPressureData)>
    ) -> [SafeRepresentation] {
        samples.map { .init($1) }
    }
}
