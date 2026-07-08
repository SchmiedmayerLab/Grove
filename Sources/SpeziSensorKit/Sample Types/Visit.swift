//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreLocation
public import Foundation
public import SensorKit


@available(iOS 17, *)
extension SRVisit: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the sample was recorded.
        public let timestamp: Date
        /// An identifier for the location of interest.
        /// This can be used to identify the same location regardless of type
        public let locationId: UUID
        /// The distance between the location of interest to home
        public let distanceFromHome: CLLocationDistance
        /// The range of time the arrival to a location of interest occurred
        public let arrivalDateInterval: DateInterval
        /// The range of time the departure from a location of interest occurred
        public let departureDateInterval: DateInterval
        /// The location’s type.
        public let locationCategory: SRVisit.LocationCategory
        
        public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(timestamp: Date, visit: SRVisit) {
            self.timestamp = timestamp
            self.locationId = visit.identifier
            self.distanceFromHome = visit.distanceFromHome
            self.arrivalDateInterval = visit.arrivalDateInterval
            self.departureDateInterval = visit.departureDateInterval
            self.locationCategory = visit.locationCategory
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRVisit)>
    ) throws -> [SafeRepresentation] {
        samples.map {
            SafeRepresentation(timestamp: $0, visit: $1)
        }
    }
}
