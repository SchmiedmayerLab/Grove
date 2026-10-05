//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import HealthKit


/// A heartbeat series and its already-enumerated beats, as ``HealthKitFHIRExporter/Record/heartbeatSeries(_:beats:)``
/// carries them.
///
/// A series keeps its beats outside the sample, so the conversion cannot read them itself. The
/// caller runs `HKHeartbeatSeriesQuery` and hands the complete enumeration over, exactly as an
/// electrocardiogram's voltage measurements are supplied.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitHeartbeatSeriesRecord: Sendable {
    let series: HKHeartbeatSeriesSample
    let heartbeats: [HealthKitFHIRExporter.Record.Heartbeat]

    init(series: HKHeartbeatSeriesSample, heartbeats: [HealthKitFHIRExporter.Record.Heartbeat]) {
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


/// All already-fetched evidence required to convert one HealthKit ECG without querying HealthKit from the FHIR layer:
/// what ``HealthKitFHIRExporter/Record/electrocardiogram(_:voltages:symptoms:)`` carries.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGRecord: Sendable {
    let electrocardiogram: HKElectrocardiogram
    let voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement]
    let correlatedSymptoms: [HKCategorySample]

    init(
        electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = []
    ) {
        self.electrocardiogram = electrocardiogram
        self.voltageMeasurements = voltageMeasurements
        self.correlatedSymptoms = correlatedSymptoms
    }
}

#endif
