//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


extension CMOdometerData: SensorKitSampleProtocol {
    /// Every public field of an odometer record, copied on the SensorKit callback thread.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The start of the interval the record covers.
        public let startDate: Date
        /// The end of the interval the record covers.
        public let endDate: Date
        /// The time of the GPS measurement associated with the location.
        public let gpsDate: Date
        /// The instantaneous velocity of the device, in meters per second.
        public let speed: Double
        public let speedAccuracy: Double
        /// The slope toward the direction of travel, in degrees.
        public let slope: Double?
        /// The maximum absolute slope toward all directions, in degrees.
        public let maxAbsSlope: Double?
        /// The distance travelled since the last location, in meters.
        public let deltaDistance: Double
        public let deltaDistanceAccuracy: Double
        /// The change in altitude above mean sea level, in meters.
        public let deltaAltitude: Double
        public let verticalAccuracy: Double
        public let originDevice: CMOdometerOriginDevice

        /// The interval the record covers, which is empty for a record whose end does not follow its start.
        public var timeRange: Range<Date> {
            startDate..<max(startDate, endDate)
        }

        /// Creates an odometer record.
        public init(
            startDate: Date,
            endDate: Date,
            gpsDate: Date,
            speed: Double,
            speedAccuracy: Double,
            slope: Double?,
            maxAbsSlope: Double?,
            deltaDistance: Double,
            deltaDistanceAccuracy: Double,
            deltaAltitude: Double,
            verticalAccuracy: Double,
            originDevice: CMOdometerOriginDevice
        ) {
            self.startDate = startDate
            self.endDate = endDate
            self.gpsDate = gpsDate
            self.speed = speed
            self.speedAccuracy = speedAccuracy
            self.slope = slope
            self.maxAbsSlope = maxAbsSlope
            self.deltaDistance = deltaDistance
            self.deltaDistanceAccuracy = deltaDistanceAccuracy
            self.deltaAltitude = deltaAltitude
            self.verticalAccuracy = verticalAccuracy
            self.originDevice = originDevice
        }

        init(_ data: CMOdometerData) {
            self.init(
                startDate: data.startDate,
                endDate: data.endDate,
                gpsDate: data.gpsDate,
                speed: data.speed,
                speedAccuracy: data.speedAccuracy,
                slope: data.slope,
                maxAbsSlope: data.maxAbsSlope,
                deltaDistance: data.deltaDistance,
                deltaDistanceAccuracy: data.deltaDistanceAccuracy,
                deltaAltitude: data.deltaAltitude,
                verticalAccuracy: data.verticalAccuracy,
                originDevice: data.originDevice
            )
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMOdometerData)>
    ) -> [SafeRepresentation] {
        samples.map { SafeRepresentation($0.sample) }
    }
}
