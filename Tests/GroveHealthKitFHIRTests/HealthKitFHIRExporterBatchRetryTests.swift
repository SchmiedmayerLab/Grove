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

    func classify(_ source: HKSource) -> HealthKitFHIRExporter.WriterPolicy.Classification {
        lock.lock()
        consultations += 1
        let isFirst = consultations == 1
        lock.unlock()
        return isFirst || !flips ? .application : .omit
    }
}


/// A call that names one record twice, and what the policy closures answer for each input.
@Suite
struct HealthKitFHIRExporterBatchRetryTests {
    private typealias Fixtures = ExporterFixtures

    @Test("Two deletions of one record with different bounds share the retraction key, and the first accepted wins")
    func twoBoundsOfOneRecordShareTheirKey() async throws {
        let exporter = try Fixtures.exporter()
        let deletions = [
            Fixtures.deletion(0xC0, deletedAfter: GoldenFixtures.sampleStart),
            Fixtures.deletion(0xC0, deletedAfter: nil),
            // A control: another record.
            Fixtures.deletion(0xC1, deletedAfter: GoldenFixtures.sampleStart)
        ]
        let retractions = try await Fixtures.retract(exporter, deletions)
        let records = retractions.compactMap(\.record)
        try #require(records.count == 3)
        #expect(records[0].version == records[1].version, "the key is a function of the source record alone")
        #expect(records[0].json != records[1].json, "the bounds are content, which the key does not cover")
        #expect(records[2].version != records[0].version)

        var packer = ExchangeBundlePacker(kind: .retraction)
        #expect(try packer.add(records[0]) == .added)
        #expect(try packer.add(records[1]) == .duplicate)
        #expect(try packer.add(records[2]) == .added)
    }

    @Test("A call naming one ECG under two symptom sets delivers each input as it states it")
    func twoSymptomSetsOfOneRecordAreTwoVersions() async throws {
        let exporter = try Fixtures.exporter()
        let one = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC3))
        let two = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC4), type: .fatigue)
        let inputs = [
            try Fixtures.electrocardiogram(uuid: 0xC2, symptoms: [one]),
            try Fixtures.electrocardiogram(uuid: 0xC2, symptoms: [two, one])
        ]
        let exports = try await Fixtures.collect(exporter, inputs)
        let retry = try await Fixtures.collect(exporter, inputs)
        let ecg = try #require(inputs.first?.sample.uuid)
        // Each ECG, then its symptoms: nothing refuses a second version of a record.
        try #require(exports.map(\.source.uuid) == [ecg, one.uuid, ecg, one.uuid, two.uuid])
        #expect(exports[0].record?.sourceRecord == exports[2].record?.sourceRecord)
        #expect(exports[0].record?.version != exports[2].record?.version)
        #expect(exports[1].record == exports[3].record, "one symptom is one record, whichever ECG correlates it")
        #expect(retry.map(\.record) == exports.map(\.record), "an exact retry repeats every record version")
    }

    @Test("A classify closure is consulted once per input naming a record, an ECG's symptoms included")
    func classifierIsConsultedPerInput() async throws {
        let classifier = CountingClassifier(flips: false)
        let exporter = try Fixtures.exporter { $0.writer = .classify { classifier.classify($0) } }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC5), writer: GoldenFixtures.foreignWriter)
        let twice = try await Fixtures.collect(exporter, samples: [sample, sample])
        #expect(classifier.count == 2)
        #expect(twice.count == 2 && twice[0].record == twice[1].record)
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC7))
        let named = try await Fixtures.collect(exporter, [Fixtures.electrocardiogram(uuid: 0xC6, symptoms: [symptom]), .sample(symptom)])
        // The ECG, its symptom inside the ECG's input, and the standalone symptom.
        #expect(classifier.count == 5)
        let symptomRecords = named.filter { $0.source.uuid == symptom.uuid }.map(\.record)
        #expect(symptomRecords.count == 2 && symptomRecords[0] == symptomRecords[1])
    }

    /// The later input names the symptom itself or correlates it with an ECG; either way each input states what the closure
    /// answered for it.
    @Test("A closure answering otherwise for a record the call named before makes the later input another version", arguments: [false, true])
    func changedAnswerWithinACallIsAnotherVersion(throughElectrocardiogram: Bool) async throws {
        let classifier = CountingClassifier(flips: true)
        let exporter = try Fixtures.exporter { $0.writer = .classify { classifier.classify($0) } }
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC9))
        let later: HealthKitFHIRExporter.Record = try throughElectrocardiogram
            ? Fixtures.electrocardiogram(uuid: 0xC8, symptoms: [symptom])
            : .sample(symptom)
        let exports = try await Fixtures.collect(exporter, [.sample(symptom), later])
        let records = exports.filter { $0.source.uuid == symptom.uuid }.compactMap(\.record)
        try #require(records.count == 2)
        #expect(records[0].sourceRecord == records[1].sourceRecord)
        #expect(records[0].version != records[1].version)
    }
}

#endif
