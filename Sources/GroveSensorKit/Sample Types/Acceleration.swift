//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


extension CMRecordedAccelerometerData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the sample was recorded.
        public let timestamp: Date
        /// The unique identifier for the accelerometer data.
        ///
        /// Accelerometer data is recorded in batches, which are assigned a unique identifier. This property contains the identifier of the batch in which this particular sample was recorded.
        public let identifier: UInt64
        /// The acceleration measured by the accelerometer.
        public let acceleration: CMAcceleration
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(_ data: CMRecordedAccelerometerData) {
            timestamp = data.startDate
            identifier = data.identifier
            acceleration = data.acceleration
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMRecordedAccelerometerData)>
    ) -> [SafeRepresentation] {
        samples.map { .init($0.sample) }
    }
}


extension CMAcceleration: @retroactive Equatable, @retroactive Hashable {
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}
