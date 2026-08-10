//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension CMHighFrequencyHeartRateData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the sample was recorded
        public let timestamp: Date
        public let value: Double
        public let confidence: CMHighFrequencyHeartRateDataConfidence
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(timestamp: Date, sample: CMHighFrequencyHeartRateData) {
            self.timestamp = sample.date ?? timestamp
            self.value = sample.heartRate
            self.confidence = sample.confidence
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMHighFrequencyHeartRateData)>
    ) -> [SafeRepresentation] {
        samples.map { .init(timestamp: $0, sample: $1) }
    }
}
