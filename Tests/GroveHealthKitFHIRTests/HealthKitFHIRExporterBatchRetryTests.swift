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


/// A writer classifier that counts its consultations and answers `.application`, or, when it `flips`, `.omit` to every
/// consultation after the first, as one reading mutable state.
private final class CountingClassifier: @unchecked Sendable { // `consultations` is guarded by `lock`.
    let flips: Bool
    private let lock = NSLock()
    private var consultations = 0

    var count: Int {
        lock.lock()
        let count = consultations
        lock.unlock()
        return count
    }

    init(flips: Bool) {
        self.flips = flips
    }

    func classify(_ source: HKSource) -> HealthKitWriter {
        lock.lock()
        consultations += 1
        let isFirst = consultations == 1
        lock.unlock()
        return isFirst || !flips ? .application : .omit
    }
}


/// A call that names one record twice: an exact retry before release, with different content, and what the policy
/// closures answer for each input.
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

    @Test("A classify closure is consulted once per input naming a record, an ECG's symptoms included")
    func classifierIsConsultedPerInput() throws {
        let classifier = CountingClassifier(flips: false)
        let exporter = try Fixtures.exporter { $0.writer = .classify { classifier.classify($0) } }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC5), writer: GoldenFixtures.foreignWriter)
        let twice = try Fixtures.collect(exporter, samples: [sample, sample])
        #expect(classifier.count == 2)
        #expect(twice.exports.count == 2 && twice.exports[0].event == twice.exports[1].event)
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC7))
        let named = try Fixtures.collect(exporter, [Fixtures.electrocardiogram(uuid: 0xC6, symptoms: [symptom]), .record(.sample(symptom))])
        // The ECG, its symptom inside the ECG's input, and the standalone symptom.
        #expect(classifier.count == 5)
        let symptomEvents = named.exports.filter { $0.source.uuid == symptom.uuid }.map(\.event)
        #expect(symptomEvents.count == 2 && symptomEvents[0] == symptomEvents[1])
        twice.receipt.release()
        named.receipt.release()
    }

    /// The later input names the symptom itself or correlates it with an ECG; either way it is refused, and no event is
    /// restated with another writer.
    @Test("A closure answering otherwise for a record the call named before refuses the later input", arguments: [false, true])
    func changedAnswerWithinACallRefusesTheLaterInput(throughElectrocardiogram: Bool) throws {
        let classifier = CountingClassifier(flips: true)
        let exporter = try Fixtures.exporter { $0.writer = .classify { classifier.classify($0) } }
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC9))
        let later: HealthKitFHIRExporter.Input = try throughElectrocardiogram
            ? Fixtures.electrocardiogram(uuid: 0xC8, symptoms: [symptom])
            : .record(.sample(symptom))
        let (exports, receipt) = try Fixtures.collect(exporter, [.record(.sample(symptom)), later])
        try #require(exports.count == 2)
        #expect(exports[0].graph != nil)
        guard case .refused(let reason) = exports[1].outcome else {
            Issue.record("expected the later input to be refused, got \(exports[1].outcome)")
            return
        }
        #expect(reason == .conflictingDuplicate)
        receipt.release()
    }
}

#endif
