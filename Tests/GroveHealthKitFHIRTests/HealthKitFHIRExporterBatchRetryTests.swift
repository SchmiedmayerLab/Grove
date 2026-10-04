//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// An exact retry, before release, of a call that names one record twice with different content.
@Suite
struct HealthKitFHIRExporterBatchRetryTests {
    private typealias Fixtures = ExporterFixtures

    @Test("An exact retry of two deletions of one record with different bounds in one call redelivers both events")
    func retryOfTwoBoundsInOneCallIsExact() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(sequencer: ExchangeEventSequencer(storage: storage))
        let deletions = [
            Fixtures.deletion(0xC0, deletedAfter: GoldenFixtures.sampleStart),
            Fixtures.deletion(0xC0, deletedAfter: nil),
            // A control: another record under one fingerprint.
            Fixtures.deletion(0xC1, deletedAfter: GoldenFixtures.sampleStart)
        ]
        let first = try Fixtures.retract(exporter, deletions)
        _ = storage.take()
        let retry = try Fixtures.retract(exporter, deletions)
        let writes = storage.take().writes
        try #require(first.exports.count == 3 && retry.exports.count == 3)
        #expect(first.exports[0].event != first.exports[1].event, "two bounds are two events")
        #expect(retry.exports[2].sequence == first.exports[2].sequence, "control: a single-fingerprint key is reused")
        #expect(retry.exports[0..<2].map(\.sequence) == first.exports[0..<2].map(\.sequence))
        #expect(retry.exports.map(\.graph?.json) == first.exports.map(\.graph?.json))
        #expect(writes == 0, "an exact retry writes nothing")
        first.receipt.release()
        retry.receipt.release()
    }

    @Test("A call naming one ECG under two symptom sets refuses the later one, and its exact retry reuses every event")
    func retryOfTwoSymptomSetsInOneCallIsExact() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(sequencer: ExchangeEventSequencer(storage: storage))
        let one = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC3))
        let two = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC4), type: .fatigue)
        let inputs = [
            try Fixtures.electrocardiogram(uuid: 0xC2, symptoms: [one]),
            try Fixtures.electrocardiogram(uuid: 0xC2, symptoms: [two, one])
        ]
        let first = try Fixtures.collect(exporter, inputs)
        _ = storage.take()
        let retry = try Fixtures.collect(exporter, inputs)
        let writes = storage.take().writes
        let ecg = try #require(inputs.first?.sample.uuid)
        // The first input's ECG and its symptom, then the later input refused: one event per key and call.
        try #require(first.exports.map(\.source.uuid) == [ecg, one.uuid, ecg])
        #expect(first.exports[0].graph != nil && first.exports[1].graph != nil)
        guard case .refused(let reason) = first.exports[2].outcome else {
            Issue.record("expected the later input to be refused, got \(first.exports[2].outcome)")
            return
        }
        #expect(reason == .conflictingDuplicate)
        #expect(reason.diagnostic == ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: "HKSample"))
        #expect(retry.exports.map(\.event) == first.exports.map(\.event))
        #expect(retry.exports.map(\.graph?.json) == first.exports.map(\.graph?.json))
        #expect(writes == 0, "an exact retry writes nothing")
        first.receipt.release()
        retry.receipt.release()
    }
}

#endif
