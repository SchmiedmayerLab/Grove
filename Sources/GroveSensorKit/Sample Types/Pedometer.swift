//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


extension CMPedometerData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public let timeRange: Range<Date>
        public let numberOfSteps: Int
        public let distance: Double? // m
        public let floorsAscended: Int?
        public let floorsDescended: Int?
        public let currentPace: Double? // m/s
        public let currentCadence: Double? // steps/s
        public let averageActivePace: Double? // s/m
        
        @inlinable
        init(_ data: CMPedometerData) {
            timeRange = data.startDate..<data.endDate
            numberOfSteps = data.numberOfSteps.intValue
            distance = data.distance?.doubleValue
            floorsAscended = data.floorsAscended?.intValue
            floorsDescended = data.floorsDescended?.intValue
            currentPace = data.currentPace?.doubleValue
            currentCadence = data.currentCadence?.doubleValue
            averageActivePace = data.averageActivePace?.doubleValue
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMPedometerData)>
    ) -> [SafeRepresentation] {
        samples.map { .init($1) }
    }
}
