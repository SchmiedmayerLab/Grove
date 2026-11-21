//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


struct HealthKitRecordingTimeTests {
    @Test(arguments: [false, true])
    func recordingPeriodPreservesSourceTimeAndZoneWithoutFallbackMetadata(route: Bool) throws {
        // The interval crosses the autumn offset transition; each endpoint keeps its own offset.
        let start = Date(timeIntervalSince1970: 1_793_520_000)
        let end = start.addingTimeInterval(7_200)
        let conversion = try Self.convert(route: route, start: start, end: end, zone: "America/Los_Angeles")
        let document = try #require(conversion.record.bundle.entry?.compactMap { $0.resource?.get(if: DocumentReference.self) }.first)
        let period = try #require(document.context?.period)
        #expect(try #require(period.start?.value).asNSDate() == start)
        #expect(try #require(period.end?.value).asNSDate() == end)
        #expect(period.start?.value?.timeZone?.secondsFromGMT() != period.end?.value?.timeZone?.secondsFromGMT())
        for endpoint in [period.start, period.end] {
            let zone = try #require(endpoint?.extension?.first { $0.url == Canonicals.timezone })
            #expect(zone.value == .code("America/Los_Angeles"))
        }
        #expect(document.extension?.contains { $0.url.value?.url.absoluteString == HealthKitSourceMetadata.url } != true)
        #expect(conversion.metadataSummary.preservedSampleKeys == 0)
    }

    @Test(arguments: [false, true])
    func missingZoneKeepsThePeriodAndDoesNotInventAName(route: Bool) throws {
        let start = GoldenFixtures.sampleStart
        let conversion = try Self.convert(route: route, start: start, end: start, zone: nil)
        let document = try #require(conversion.record.bundle.entry?.compactMap { $0.resource?.get(if: DocumentReference.self) }.first)
        let period = try #require(document.context?.period)
        #expect(period.start == period.end)
        #expect(try #require(period.start?.value).asNSDate() == start)
        #expect(period.start?.extension == nil && period.end?.extension == nil)
    }

    @Test(arguments: [false, true])
    func invalidSourceTimingCannotBeHiddenInMetadata(route: Bool) throws {
        let start = GoldenFixtures.sampleStart
        #expect(throws: HealthKitConversionError.ValueFailure.unsupportedMetadataValue(.timeZone)) {
            try Self.convert(route: route, start: start, end: start, zone: "not/a/time-zone")
        }
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try Self.convert(route: route, start: start, end: start.addingTimeInterval(-1), zone: nil)
        }
    }
}


extension HealthKitRecordingTimeTests {
    private static func convert(route: Bool, start: Date, end: Date, zone: String?) throws -> HealthKitAssembly.Conversion {
        let facts = StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(0xF8),
            start: start,
            end: end,
            device: nil,
            metadata: zone.map { [HKMetadataKeyTimeZone: $0] },
            writer: GoldenFixtures.foreignWriter
        )
        let record: HealthKitFHIRExporter.Record
        if route {
            let sample = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: facts)
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
                altitude: 10,
                horizontalAccuracy: 1,
                verticalAccuracy: 1,
                timestamp: start
            )
            record = .workoutRoute(sample, locations: [location])
        } else {
            let sample = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
            record = .heartbeatSeries(sample, beats: [.init(timeSinceSeriesStart: 0, precededByGap: false)])
        }
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        return try #require(try AssemblyFixtures.conversions(record, inputs).first)
    }
}

#endif
