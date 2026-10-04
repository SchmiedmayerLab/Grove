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
        _ record: HealthKitFHIRExporter.Record
    ) throws -> HealthKitFHIRExporter.Export {
        let (exports, _) = try Fixtures.collect(exporter, [record])
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
            facts: GoldenCase.seriesFacts(uuid: 0xF0, duration: 2)
        )
        var changedBeats = Self.beats
        changedBeats[1] = HealthKitHeartbeat(timeSinceSeriesStart: 0.85, precededByGap: false)
        let original = try Self.primary(exporter, .heartbeatSeries(series, beats: Self.beats))
        let exact = try Self.primary(exporter, .heartbeatSeries(series, beats: Self.beats))
        let changed = try Self.primary(exporter, .heartbeatSeries(series, beats: changedBeats))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Locations: one changed location under a reserved workout route takes a new sequence")
    func changedLocationTakesANewSequence() throws {
        let exporter = try Fixtures.exporter { $0.route = .authorized }
        let route = try StoredSampleFixtures.seriesSample(
            HKWorkoutRoute.self,
            sampleType: HKSeriesType.workoutRoute(),
            facts: GoldenCase.seriesFacts(uuid: 0xF1, duration: 1)
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
        let original = try Self.primary(exporter, .workoutRoute(route, locations: GoldenCase.routeLocations))
        let exact = try Self.primary(exporter, .workoutRoute(route, locations: GoldenCase.routeLocations))
        let changed = try Self.primary(exporter, .workoutRoute(route, locations: changedLocations))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// The stored-sample fixtures state the voltages, so the ECG arrives as the public `.electrocardiogram` record, whose
    /// record parts state its symptoms and voltages.
    @Test("Voltages: one changed voltage under a reserved ECG takes a new sequence")
    func changedVoltageTakesANewSequence() throws {
        let exporter = try Fixtures.exporter()
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xF2, symptoms: [])
        var changedVoltages = record.voltageMeasurements
        changedVoltages[1] = try StoredSampleFixtures.voltageMeasurement(offset: changedVoltages[1].timeSinceSampleStart, millivolts: 0.375)
        let original = try Self.primary(exporter, Fixtures.electrocardiogram(record, symptoms: []))
        let exact = try Self.primary(exporter, Fixtures.electrocardiogram(record, symptoms: []))
        let changed = try Self.primary(exporter, .electrocardiogram(record.electrocardiogram, voltages: changedVoltages, symptoms: []))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// Two exporters over one ledger, as before and after an app update that changed what its resolver returns.
    @Test("Custom resolver: a resolver naming another device under a reserved record takes a new sequence")
    func changedCustomResolverTakesANewSequence() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let before = try Fixtures.exporter(storage: storage) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let after = try Fixtures.exporter(storage: storage) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-b")) }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF3), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let original = try Self.primary(before, .sample(sample))
        let exact = try Self.primary(before, .sample(sample))
        let changed = try Self.primary(after, .sample(sample))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Custom resolver: a resolver naming the same unit otherwise under a reserved record takes a new sequence")
    func renamedCustomResolverTakesANewSequence() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let before = try Fixtures.exporter(storage: storage) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let after = try Fixtures.exporter(storage: storage) {
            $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a", name: "Left Wrist"))
        }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF4), device: GoldenFixtures.watch)
        let original = try Self.primary(before, .sample(sample))
        let exact = try Self.primary(before, .sample(sample))
        let changed = try Self.primary(after, .sample(sample))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    @Test("Classify: a closure classifying a reserved record's source otherwise takes a new sequence")
    func changedClassificationTakesANewSequence() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let before = try Fixtures.exporter(storage: storage) { $0.writer = .classify { _ in .application } }
        let after = try Fixtures.exporter(storage: storage) { $0.writer = .classify { _ in .omit } }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF5), writer: GoldenFixtures.foreignWriter)
        let original = try Self.primary(before, .sample(sample))
        let exact = try Self.primary(before, .sample(sample))
        let changed = try Self.primary(after, .sample(sample))
        try Self.expectNoReuse(original: original, exact: exact, changed: changed)
    }

    /// What is fingerprinted is what is emitted: a resolver consulted again for the graph would state `unit-b` under the
    /// event fingerprinted for `unit-a`, which a fixed `unit-a` resolver would then reuse with other bytes.
    @Test("Custom resolver: consulted once per input, so the graph states the device its fingerprint covers")
    func customResolverIsConsultedOncePerInput() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let changing = try Fixtures.exporter(storage: storage) { $0.recordingDevice = .custom(FirstAnswerResolver()) }
        let fixed = try Fixtures.exporter(storage: storage) { $0.recordingDevice = .custom(FixedUnitResolver(token: "unit-a")) }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xF6), device: GoldenFixtures.watch)
        let first = try Self.primary(changing, .sample(sample))
        let again = try Self.primary(fixed, .sample(sample))
        #expect(again.event == first.event, "both fingerprint unit-a")
        #expect(again.graph?.json == first.graph?.json, "the first graph states unit-a, the device it was fingerprinted under")
    }
}

#endif
