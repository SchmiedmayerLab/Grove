//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The public recording inputs and their graph result form one small contract inventory.
// swiftlint:disable file_types_order

#if canImport(HealthKit)

public import CoreLocation
public import Foundation
public import HealthKit


/// One beat instant in a heartbeat series, as `HKHeartbeatSeriesQuery` enumerates it.
public struct HealthKitHeartbeat: Hashable, Sendable {
    public let timeSinceSeriesStart: TimeInterval
    public let precededByGap: Bool

    public init(timeSinceSeriesStart: TimeInterval, precededByGap: Bool) {
        self.timeSinceSeriesStart = timeSinceSeriesStart
        self.precededByGap = precededByGap
    }
}


/// A heartbeat series and its already-enumerated beats.
///
/// A series keeps its beats outside the sample, so the conversion cannot read them itself. The
/// caller runs `HKHeartbeatSeriesQuery` and hands the complete enumeration over, exactly as an
/// electrocardiogram's voltage measurements are supplied.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitHeartbeatSeriesRecord: Sendable {
    public let series: HKHeartbeatSeriesSample
    public let heartbeats: [HealthKitHeartbeat]

    public init(series: HKHeartbeatSeriesSample, heartbeats: [HealthKitHeartbeat]) {
        self.series = series
        self.heartbeats = heartbeats
    }
}


/// A workout route and its already-enumerated location fixes.
///
/// The fixes come from `HKWorkoutRouteQuery`; whether they may be disclosed at all is
/// `RouteDisclosurePolicy` on the conversion context.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitWorkoutRouteRecord: Sendable {
    public let route: HKWorkoutRoute
    public let locations: [CLLocation]

    public init(route: HKWorkoutRoute, locations: [CLLocation]) {
        self.route = route
        self.locations = locations
    }
}


#endif
