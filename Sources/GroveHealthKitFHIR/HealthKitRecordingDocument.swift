//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// A beat series' beats and the two recording records read as one small inventory.
// swiftlint:disable file_types_order

#if canImport(HealthKit)

import CoreLocation
public import Foundation
import HealthKit


/// One beat instant in a heartbeat series, as `HKHeartbeatSeriesQuery` enumerates it.
public struct HealthKitHeartbeat: Hashable, Sendable {
    public let timeSinceSeriesStart: TimeInterval
    public let precededByGap: Bool

    public init(timeSinceSeriesStart: TimeInterval, precededByGap: Bool) {
        self.timeSinceSeriesStart = timeSinceSeriesStart
        self.precededByGap = precededByGap
    }
}


/// A heartbeat series and its already-enumerated beats, as ``HealthKitFHIRExporter/Record/heartbeatSeries(_:beats:)``
/// carries them.
///
/// A series keeps its beats outside the sample, so the conversion cannot read them itself. The
/// caller runs `HKHeartbeatSeriesQuery` and hands the complete enumeration over, exactly as an
/// electrocardiogram's voltage measurements are supplied.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitHeartbeatSeriesRecord: Sendable {
    let series: HKHeartbeatSeriesSample
    let heartbeats: [HealthKitHeartbeat]

    init(series: HKHeartbeatSeriesSample, heartbeats: [HealthKitHeartbeat]) {
        self.series = series
        self.heartbeats = heartbeats
    }
}


/// A workout route and its already-enumerated location fixes, as
/// ``HealthKitFHIRExporter/Record/workoutRoute(_:locations:)`` carries them.
///
/// The fixes come from `HKWorkoutRouteQuery`; whether they may be disclosed at all is
/// ``HealthKitFHIRExporter/Options/route``.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitWorkoutRouteRecord: Sendable {
    let route: HKWorkoutRoute
    let locations: [CLLocation]

    init(route: HKWorkoutRoute, locations: [CLLocation]) {
        self.route = route
        self.locations = locations
    }
}


#endif
