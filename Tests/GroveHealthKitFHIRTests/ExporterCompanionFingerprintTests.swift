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
import Testing


/// A deployment resolver that names every device by one fixed per-unit token and name.
private struct FixedUnitResolver: RecordingDeviceResolver {
    let token: String
    var name = "Apple Watch"

    func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        try? RecordingDevice(stableUnitToken: token, name: name)
    }
}


/// A resolver whose first answer is `unit-a` and every later one `unit-b`, as one reading mutable pairing state.
private final class FirstAnswerResolver: RecordingDeviceResolver, @unchecked Sendable { // `answered` is guarded by `lock`.
    private let lock = NSLock()
    private var answered = false

    func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        lock.lock()
        let token = answered ? "unit-b" : "unit-a"
        answered = true
        lock.unlock()
        return try? RecordingDevice(stableUnitToken: token, name: "Apple Watch")
    }
}


/// The IG's retry rule (`catalog/exchange-protocol.json`, `event.retry`): an exact retry reuses the event, and any
/// content change receives a new sequence. Each case exports a record, drops the receipt unreleased (its hold
/// lapses, the reservation stays, as after a failed upload), then redelivers the same sample with one input that
/// changes the graph bytes: companion data, or what a policy closure answers for the record.
@Suite
struct ExporterCompanionFingerprintTests {
    private typealias Fixtures = ExporterFixtures

    private static let beats = [
        HealthKitHeartbeat(timeSinceSeriesStart: 0, precededByGap: false),
        HealthKitHeartbeat(timeSinceSeriesStart: 0.84, precededByGap: false),
        HealthKitHeartbeat(timeSinceSeriesStart: 1.71, precededByGap: true)
    ]

    /// The primary export of one call; the receipt is dropped without release, so the reservation stays.
    private static func primary(
        _ exporter: HealthKitFHIRExporter,
        _ input: HealthKitFHIRExporter.Input
    ) throws -> HealthKitFHIRExporter.Export {
        let (exports, _) = try Fixtures.collect(exporter, [input])
        return try #require(exports.first)
    }

    /// An exact redelivery reuses the event byte for byte; a redelivery whose bytes changed must not reuse it.
    private static func expectNoReuse(
        original: HealthKitFHIRExporter.Export,
        exact: HealthKitFHIRExporter.Export,
        changed: HealthKitFHIRExporter.Export,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let originalJSON = try #require(original.graph?.json, "original: \(original.outcome)", sourceLocation: sourceLocation)
        let changedJSON = try #require(changed.graph?.json, "changed: \(changed.outcome)", sourceLocation: sourceLocation)
        try #require(exact.event == original.event, "an exact redelivery reuses the event", sourceLocation: sourceLocation)
        try #require(exact.graph?.json == originalJSON, "an exact redelivery is byte-identical", sourceLocation: sourceLocation)
        try #require(changedJSON != originalJSON, "the companion change must change the graph bytes", sourceLocation: sourceLocation)
        #expect(
            changed.event != original.event,
            "event sequence \(original.sequence ?? "nil") was reused for different graph bytes",
            sourceLocation: sourceLocation
        )
    }

    @Test("Beats: one changed beat under a reserved heartbeat series takes a new sequence")
    func changedBeatTakesANewSequence() throws {
        let exporter = try Fixtures.exporter()
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            shape: GoldenCase.seriesShape(uuid: 0xF0, duration: 2)
        )
        var changedBeats = Self.beats
        changedBeats[1] = HealthKitHeartbeat(timeSinceSeriesStart: 0.85, precededByGap: false)
        let original = try Self.primary(exporter, .record(.heartbeatSeries(series, beats: Self.beats)))
        let exact = try Self.primary(exporter, .record(.heartbeatSeries(series, beats: Self.beats)))
        let changed = try Self.primary(exporter, .record(.heartbeatSeries(series, beats: changedBeats)))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Locations: one changed location under a reserved workout route takes a new sequence")
    func changedLocationTakesANewSequence() throws {
        let exporter = try Fixtures.exporter { $0.route = .authorized }
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            shape: GoldenCase.seriesShape(uuid: 0xF1, duration: 1)
        )
        var changedLocations = GoldenCase.routeLocations
        let moved = changedLocations[1]
        changedLocations[1] = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: moved.coordinate.latitude + 0.0001, longitude: moved.coordinate.longitude),
            altitude: moved.altitude,
            horizontalAccuracy: moved.horizontalAccuracy,
            verticalAccuracy: moved.verticalAccuracy,
            course: moved.course,
            courseAccuracy: moved.courseAccuracy,
            speed: moved.speed,
            speedAccuracy: moved.speedAccuracy,
            timestamp: moved.timestamp
        )
        let original = try Self.primary(exporter, .record(.workoutRoute(route, locations: GoldenCase.routeLocations)))
        let exact = try Self.primary(exporter, .record(.workoutRoute(route, locations: GoldenCase.routeLocations)))
        let changed = try Self.primary(exporter, .record(.workoutRoute(route, locations: changedLocations)))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// `HKElectrocardiogram.VoltageMeasurement` cannot be built outside HealthKit, so the voltages arrive through the
    /// evidence seam, whose record parts are the same as the public `.electrocardiogram` record's: the symptoms only.
    @Test("Voltages: one changed voltage under a reserved ECG takes a new sequence")
    func changedVoltageTakesANewSequence() throws {
        let exporter = try Fixtures.exporter()
        let (ecg, evidence) = try GoldenCase.electrocardiogramEvidence(uuid: 0xF2, symptomsPresent: false)
        let changedWaveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: evidence.source.numberOfVoltageMeasurements,
            samplingFrequencyHertz: evidence.source.samplingFrequency,
            points: [
                HealthKitECGVoltagePoint(timeSinceSampleStart: 0.250, millivolts: 0.125),
                HealthKitECGVoltagePoint(timeSinceSampleStart: 0.252, millivolts: 0.375),
                HealthKitECGVoltagePoint(timeSinceSampleStart: 0.254, millivolts: -0.125),
                HealthKitECGVoltagePoint(timeSinceSampleStart: 0.256, millivolts: 0)
            ]
        )
        let changedEvidence = HealthKitECGEvidence(source: evidence.source, waveform: changedWaveform)
        let original = try Self.primary(exporter, .electrocardiogramEvidence(ecg, evidence: evidence, symptoms: []))
        let exact = try Self.primary(exporter, .electrocardiogramEvidence(ecg, evidence: evidence, symptoms: []))
        let changed = try Self.primary(exporter, .electrocardiogramEvidence(ecg, evidence: changedEvidence, symptoms: []))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// Two exporters over one ledger, as before and after an app update that changed what its resolver returns.
    @Test("Custom resolver: a resolver naming another device under a reserved record takes a new sequence")
    func changedCustomResolverTakesANewSequence() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let before = try Fixtures.exporter(sequencer: sequencer) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let after = try Fixtures.exporter(sequencer: sequencer) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-b")) }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF3), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let original = try Self.primary(before, .record(.sample(sample)))
        let exact = try Self.primary(before, .record(.sample(sample)))
        let changed = try Self.primary(after, .record(.sample(sample)))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Custom resolver: a resolver naming the same unit otherwise under a reserved record takes a new sequence")
    func renamedCustomResolverTakesANewSequence() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let before = try Fixtures.exporter(sequencer: sequencer) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let after = try Fixtures.exporter(sequencer: sequencer) {
            $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a", name: "Left Wrist"))
        }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF4), device: GoldenFixtures.watch)
        let original = try Self.primary(before, .record(.sample(sample)))
        let exact = try Self.primary(before, .record(.sample(sample)))
        let changed = try Self.primary(after, .record(.sample(sample)))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Classify: a closure classifying a reserved record's source otherwise takes a new sequence")
    func changedClassificationTakesANewSequence() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let before = try Fixtures.exporter(sequencer: sequencer) { $0.writer = .classify { _ in .application } }
        let after = try Fixtures.exporter(sequencer: sequencer) { $0.writer = .classify { _ in .omit } }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF5), writer: GoldenFixtures.foreignWriter)
        let original = try Self.primary(before, .record(.sample(sample)))
        let exact = try Self.primary(before, .record(.sample(sample)))
        let changed = try Self.primary(after, .record(.sample(sample)))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// What is fingerprinted is what is emitted: a resolver consulted again for the graph would state `unit-b` under the
    /// event fingerprinted for `unit-a`, which a fixed `unit-a` resolver would then reuse with other bytes.
    @Test("Custom resolver: consulted once per record, so the graph states the device its fingerprint covers")
    func customResolverIsConsultedOncePerRecord() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let changing = try Fixtures.exporter(sequencer: sequencer) { $0.recordingDevice = .custom(FirstAnswerResolver()) }
        let fixed = try Fixtures.exporter(sequencer: sequencer) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF6), device: GoldenFixtures.watch)
        let first = try Self.primary(changing, .record(.sample(sample)))
        let again = try Self.primary(fixed, .record(.sample(sample)))
        #expect(again.event == first.event, "both fingerprint unit-a")
        #expect(again.graph?.json == first.graph?.json, "the first graph states unit-a, the device it was fingerprinted under")
    }
}

#endif
