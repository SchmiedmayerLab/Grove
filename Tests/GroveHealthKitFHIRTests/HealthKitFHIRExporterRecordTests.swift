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


/// Each ``HealthKitFHIRExporter/Record`` kind through `export(records:)`, and a policy that emits nothing.
@Suite
struct HealthKitFHIRExporterRecordTests {
    private typealias Fixtures = ExporterFixtures

    private static let beats = [
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0, precededByGap: false),
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0.84, precededByGap: false),
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 1.71, precededByGap: true)
    ]

    private static func exports(
        _ records: [HealthKitFHIRExporter.Record],
        _ exporter: HealthKitFHIRExporter
    ) async throws -> [HealthKitFHIRExporter.Export] {
        try await Fixtures.collect(exporter, records)
    }

    @Test("An ECG record's voltages are validated against its sample")
    func electrocardiogramRecord() async throws {
        let exporter = try Fixtures.exporter()
        // The fixture ECG states no reading, so it reports no voltage count and the record path refuses it; E2 covers
        // a converted ECG.
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            facts: GoldenCase.seriesFacts(uuid: 0xE0, duration: 30)
        )
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xE1))
        let exports = try await Self.exports([.electrocardiogram(ecg, voltages: [], symptoms: [symptom])], exporter)
        try #require(exports.count == 1)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.invalidReportedVoltageCount(0)))
    }

    @Test("A heartbeat-series record is the recording document the assembly builds")
    func heartbeatSeriesRecord() async throws {
        let exporter = try Fixtures.exporter()
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: 0xE2, duration: 2)
        )
        let exports = try await Self.exports([.heartbeatSeries(series, beats: Self.beats)], exporter)
        try #require(exports.count == 1)
        let reference = try AssemblyFixtures.conversions(.heartbeatSeries(series, beats: Self.beats))
        #expect(exports[0].record == reference.first?.record)
        #expect(exports[0].source.sourceType == .heartbeatSeries)
    }

    @Test("A workout-route record is a recording document under an authorized route policy")
    func authorizedWorkoutRouteRecord() async throws {
        let exporter = try Fixtures.exporter { $0.route = .authorized }
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: GoldenCase.seriesFacts(uuid: 0xE3, duration: 1)
        )
        let exports = try await Self.exports([.workoutRoute(route, locations: GoldenCase.routeLocations)], exporter)
        try #require(exports.count == 1)
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        let reference = try AssemblyFixtures.conversions(.workoutRoute(route, locations: GoldenCase.routeLocations), inputs)
        #expect(exports[0].record == reference.first?.record)
    }

    @Test("A route the policy omits delivers nothing, neither record nor refusal")
    func omittedWorkoutRouteDeliversNothing() async throws {
        let exporter = try Fixtures.exporter()
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: GoldenCase.seriesFacts(uuid: 0xE4, duration: 1)
        )
        let heartRate = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xE5))
        let exports = try await Self.exports([.workoutRoute(route, locations: GoldenCase.routeLocations), .sample(heartRate)], exporter)
        try #require(exports.map(\.source.uuid) == [heartRate.uuid], "the omitted route is not reported, and the export continues")
        #expect(exports[0].warnings.isEmpty)
    }

    @Test("E1: a duplicated ECG symptom is refused as a duplicate, on every OS")
    func duplicatedSymptomIsRefusedAsSuch() async throws {
        let exporter = try Fixtures.exporter()
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xE7))
        let exports = try await Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0xE6, symptoms: [symptom, symptom])])
        try #require(exports.count == 1)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.duplicateSymptomSource(symptom.uuid)))
    }

    /// The ECG and its average-heart-rate child both state an effective Period; the omission names each field once.
    @Test("An ECG without a time zone reports each effective field it states in UTC once, though its child states them too")
    func electrocardiogramReportsEachOffsetOmissionOnce() async throws {
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xE8, symptoms: [], timeZoned: false)
        let exports = try await Fixtures.collect(Fixtures.exporter(), [Fixtures.electrocardiogram(record, symptoms: [])])
        try #require(exports.count == 1)
        let observations = exports[0].record?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.count == 2, "the ECG and its average heart rate")
        #expect(exports[0].warnings == ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"].map {
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: $0)
        })
    }
}

#endif
