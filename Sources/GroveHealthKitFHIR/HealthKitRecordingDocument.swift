//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import CoreLocation
public import Foundation
public import GroveFHIRContract
public import HealthKit
public import ModelsR4


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
/// ``HealthKitRouteDisclosurePolicy`` on the conversion context.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitWorkoutRouteRecord: Sendable {
    public let route: HKWorkoutRoute
    public let locations: [CLLocation]

    public init(route: HKWorkoutRoute, locations: [CLLocation]) {
        self.route = route
        self.locations = locations
    }
}


/// Complete business identities of one emitted recording-document graph.
public struct HealthKitDocumentGraphIdentifiers: Hashable, Sendable {
    public let bundle: BusinessIdentifier
    public let document: BusinessIdentifier
    public let recordingDevice: BusinessIdentifier?
    public let converterApplication: BusinessIdentifier
    public let sourceAuthor: BusinessIdentifier?
    public let provenance: BusinessIdentifier
}


/// One complete conversion graph whose record is a recording rather than a result.
///
/// The same shape as ``HealthKitConversion`` with a `DocumentReference` in place of the
/// Observation: the sources carried this way have no scalar a single Observation value could hold.
public struct HealthKitDocumentConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let graphIdentifiers: HealthKitDocumentGraphIdentifiers
    public let document: DocumentReference
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let sourceAuthor: Device?
    public let provenance: Provenance
    public let bundle: ModelsR4.Bundle
}

#endif
