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
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.export(records: records, at: GoldenFixtures.conversionInstant) { exports.append($0) }
        return (exports, receipt)
    }

    @Test("An ECG record's voltages are validated against its sample, and a refusal holds the ECG's and its symptoms' events")
    func electrocardiogramRecord() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        // The fixture ECG states no reading, so it reports no voltage count and the record path refuses it; E2 covers
        // a converted ECG.
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            facts: GoldenCase.seriesFacts(uuid: 0xE0, duration: 30)
        )
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xE1))
        let (exports, receipt) = try Self.exports([.electrocardiogram(ecg, voltages: [], symptoms: [symptom])], exporter)
        try #require(exports.count == 1)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.invalidReportedVoltageCount(0)))
        #expect(storage.take().transactions == 1)
        let keys = try [#require(ExchangeEventKey.active(ecg)), #require(ExchangeEventKey.active(symptom))]
        #expect(try keys.allSatisfy { try storage.holdsReservation(for: $0) })
        receipt.release()
        #expect(try !keys.contains { try storage.holdsReservation(for: $0) })
    }

    @Test("A heartbeat-series record is the recording document the assembly builds under the exporter's event")
    func heartbeatSeriesRecord() throws {
        let exporter = try Fixtures.exporter()
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: 0xE2, duration: 2)
        )
        let (exports, _) = try Self.exports([.heartbeatSeries(series, beats: Self.beats)], exporter)
        try #require(exports.count == 1)
        let reference = try Fixtures.standalone(.heartbeatSeries(series, beats: Self.beats), as: exports[0].event)
        #expect(exports[0].graph?.json == reference.graph.json)
        #expect(exports[0].source.sourceType == .heartbeatSeries)
    }

    @Test("A workout-route record is a recording document under an authorized route policy")
    func authorizedWorkoutRouteRecord() throws {
        let exporter = try Fixtures.exporter { $0.route = .authorized }
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: GoldenCase.seriesFacts(uuid: 0xE3, duration: 1)
        )
        let (exports, _) = try Self.exports([.workoutRoute(route, locations: GoldenCase.routeLocations)], exporter)
        try #require(exports.count == 1)
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        let reference = try Fixtures.standalone(.workoutRoute(route, locations: GoldenCase.routeLocations), as: exports[0].event, inputs)
        #expect(exports[0].graph?.json == reference.graph.json)
    }

    @Test("A route the policy omits delivers nothing, neither graph nor refusal, and holds its event until release")
    func omittedWorkoutRouteDeliversNothing() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: GoldenCase.seriesFacts(uuid: 0xE4, duration: 1)
        )
        let heartRate = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xE5))
        let (exports, receipt) = try Self.exports([.workoutRoute(route, locations: GoldenCase.routeLocations), .sample(heartRate)], exporter)
        try #require(exports.map(\.source.uuid) == [heartRate.uuid], "the omitted route is not reported, and the export continues")
        #expect(exports[0].warnings.isEmpty)
        let key = try #require(ExchangeEventKey.active(route))
        #expect(try storage.holdsReservation(for: key))
        receipt.release()
        #expect(try !storage.holdsReservation(for: key))
    }

    @Test("E1: a duplicated ECG symptom is refused as a duplicate, on every OS")
    func duplicatedSymptomIsRefusedAsSuch() throws {
        let exporter = try Fixtures.exporter()
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xE7))
        let (exports, _) = try Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0xE6, symptoms: [symptom, symptom])])
        try #require(exports.count == 1)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.duplicateSymptomSource(symptom.uuid)))
    }

    /// The ECG and its average-heart-rate child both state an effective Period; the omission names each field once.
    @Test("An ECG without a time zone reports each effective field it states in UTC once, though its child states them too")
    func electrocardiogramReportsEachOffsetOmissionOnce() throws {
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xE8, symptoms: [], timeZoned: false)
        let (exports, _) = try Fixtures.collect(Fixtures.exporter(), [Fixtures.electrocardiogram(record, symptoms: [])])
        try #require(exports.count == 1)
        let observations = exports[0].graph?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.count == 2, "the ECG and its average heart rate")
        #expect(exports[0].warnings == ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"].map {
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: $0)
        })
    }
}

#endif
