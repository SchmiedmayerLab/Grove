//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


@available(iOS 17, *)
extension CMRecordedRotationRateData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the sample was recorded
        public let timestamp: Date
        /// The rotation rate measured by the gyroscope.
        public let rotationRate: CMRotationRate
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(_ sample: CMRecordedRotationRateData) {
            timestamp = sample.startDate
            rotationRate = sample.rotationRate
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMRecordedRotationRateData)>
    ) -> [SafeRepresentation] {
        samples.map { .init($1) }
    }
}


@available(iOS 17, *)
extension CMRotationRate: @retroactive Equatable, @retroactive Hashable {
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
