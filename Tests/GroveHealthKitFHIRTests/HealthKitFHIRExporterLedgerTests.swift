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
import ModelsR4
import Testing


/// The exporter's use of the ledger: frozen facts, holds, receipts, record-level fingerprints, ECG pairing.
@Suite
struct HealthKitFHIRExporterLedgerTests {
    private typealias Fixtures = ExporterFixtures

    /// A category type the catalog does not register, where this OS knows one (bleeding after menopause, OS 27).
    static var unregisteredCategoryType: HKCategoryTypeIdentifier? {
        let identifier = HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifierBleedingAfterMenopause")
        return HKObjectType.categoryType(forIdentifier: identifier) == nil ? nil : identifier
    }

    private static func study(revision: String) throws -> StudyEnrollment {
        try StudyEnrollment(
            study: .test(.researchStudy, "s1"),
            protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/s1")),
            protocolVersion: revision,
            enrollment: .test(.researchSubject, "enrollment-s1")
        )
    }

    /// The application versions every Device of `graph` states.
    private static func deviceVersions(_ graph: ExchangeGraph?) -> Set<String> {
        let devices = graph?.bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        return Set(devices.flatMap { $0.version ?? [] }.compactMap { $0.value.value?.string })
    }

    /// The graphs of one heart rate, one ECG with a symptom, and one retraction, under `producer`.
    private static func deliver(
        under producer: ExchangeProducer
    ) async throws -> (graphs: [ExchangeGraph?], receipts: [ExchangeProducer.Receipt]) {
        let exporter = try Fixtures.exporter(producer)
        let records: [HealthKitFHIRExporter.Record] = [
            .sample(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1))),
            try Fixtures.electrocardiogram(uuid: 2, symptoms: [try GoldenCase.symptom(uuid: GoldenFixtures.uuid(3))])
        ]
        let (exports, receipt) = try await Fixtures.collect(exporter, records)
        let (retractions, retractionReceipt) = try await Fixtures.retract(exporter, [Fixtures.deletion(4, deletedAfter: GoldenFixtures.sampleStart)])
        return (exports.map(\.graph) + retractions.map(\.graph), [receipt, retractionReceipt])
    }

    @Test("G2: a redelivery before release is byte-identical across app, OS and study changes; after release it is new")
    func redeliveryIsByteIdenticalAcrossFactChanges() async throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let original = try Fixtures.producer(
            application: .test(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0", build: "100"),
            host: try HostDevice(operatingSystemVersion: "26.0", modelNumber: "iPhone17,1"),
            studies: [],
            storage: storage
        )
        let first = try await Self.deliver(under: original)
        try #require(first.graphs.count == 4)
        var receipts = first.receipts
        // App 1.0 (100) to 1.1 (110), OS 26.0 to 27.0, studies [] to [s1 rev 1], then [s1 rev 1] to [s1 rev 2].
        let updated = try ["1", "2"].map { revision in
            try Fixtures.producer(
                application: .test(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.1", build: "110"),
                host: try HostDevice(operatingSystemVersion: "27.0", modelNumber: "iPhone17,1"),
                studies: [try Self.study(revision: revision)],
                storage: storage
            )
        }
        for producer in updated {
            let again = try await Self.deliver(under: producer)
            #expect(again.graphs.map(\.?.json) == first.graphs.map(\.?.json))
            #expect(again.graphs.map(\.?.eventIdentifier) == first.graphs.map(\.?.eventIdentifier))
            receipts += again.receipts
        }
        #expect(Self.deviceVersions(first.graphs[0]).contains("1.0"))
        receipts.forEach { $0.release() }
        let renewed = try await Self.deliver(under: try #require(updated.last))
        for (renewedGraph, firstGraph) in zip(renewed.graphs, first.graphs) {
            #expect(renewedGraph?.eventIdentifier != firstGraph?.eventIdentifier)
            #expect(renewedGraph?.json != firstGraph?.json)
        }
        #expect(Self.deviceVersions(renewed.graphs[0]).contains("1.1"))
        #expect(!Self.deviceVersions(renewed.graphs[0]).contains("1.0"))
    }

    @Test("G18: the first delivery and a redelivery through a fresh process produce byte-equal graphs")
    func redeliveryThroughAFreshProcessIsByteEqual() async throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let studies = [try Self.study(revision: "1"), StudyEnrollment.test("s2")]
        let first = try await Self.deliver(under: try Fixtures.producer(studies: studies, storage: storage, holds: HoldRegistry()))
        let again = try await Self.deliver(under: try Fixtures.producer(studies: [], storage: storage, holds: HoldRegistry()))
        #expect(again.graphs.map(\.?.json) == first.graphs.map(\.?.json))
    }

    @Test("G8: a call that throws in receive leaves its reservations; the redelivery reuses them and its release removes them")
    func throwingDeliveryLapses() async throws {
        struct Stop: Error {}
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(5))
        let key = try #require(ExchangeEventKey.active(sample))
        await #expect(throws: Stop.self) {
            try await exporter.export([sample]) { _ in throw Stop() }
        }
        #expect(try storage.holdsReservation(for: key))
        let (again, receipt) = try await Fixtures.collect(exporter, samples: [sample])
        #expect(again[0].sequence == "1")
        receipt.release()
        #expect(try !storage.holdsReservation(for: key))
    }

    @Test("G9: overlapping calls keep a shared event until the last one finishes; double releases count once")
    func overlappingReceipts() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(6))
        let key = try #require(ExchangeEventKey.active(sample))
        let (live, liveReceipt) = try await Fixtures.collect(exporter, samples: [sample])
        var bulkReceipt: ExchangeProducer.Receipt?
        do {
            let bulk = try await Fixtures.collect(exporter, samples: [sample])
            #expect(live[0].graph?.json == bulk.exports[0].graph?.json)
            bulkReceipt = bulk.receipt
        }
        // The first release, twice and through a second reference, marks the event; the slower call still holds it.
        let alias = liveReceipt
        liveReceipt.release()
        alias.release()
        liveReceipt.release()
        #expect(try storage.holdsReservation(for: key))
        let (redelivery, redeliveryReceipt) = try await Fixtures.collect(exporter, samples: [sample])
        #expect(redelivery[0].graph?.json == live[0].graph?.json, "a redelivery by the slower call is an exact retry")
        redeliveryReceipt.release()
        #expect(try storage.holdsReservation(for: key))
        // A lost compare-exchange: the remaining holder is dropped unreleased, and as the last one it removes the event.
        #expect(bulkReceipt != nil)
        bulkReceipt = nil
        #expect(try !storage.holdsReservation(for: key))
    }

    @Test("G9e: a refused ECG companion keeps the standalone symptom's event in the same call")
    func refusedCompanionKeepsTheStandaloneSymptom() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0x71))
        // Symptoms present but the ECG states none: the ECG is refused, its companion with it.
        let ecg = try GoldenCase.electrocardiogramRecord(uuid: 0x70, symptoms: [])
        let (first, receipt) = try await Fixtures.collect(exporter, [Fixtures.electrocardiogram(ecg, symptoms: [symptom]), .sample(symptom)])
        guard case .refused = first[0].outcome else {
            Issue.record("expected the ECG to be refused, got \(first[0].outcome)")
            return
        }
        let standalone = try #require(first[1].graph)
        let (again, againReceipt) = try await Fixtures.collect(exporter, samples: [symptom])
        #expect(again[0].graph?.json == standalone.json, "the symptom's event survived the refusal")
        let key = try #require(ExchangeEventKey.active(symptom))
        receipt.release()
        #expect(try storage.holdsReservation(for: key), "the redelivery still holds it")
        againReceipt.release()
        #expect(try !storage.holdsReservation(for: key))
    }

    @Test("G10: an export and its release take one ledger transaction each; an empty receipt and a reuse write nothing")
    func transactionBudget() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let samples = try (7...9).map { try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid($0)) }
        let (_, receipt) = try await Fixtures.collect(exporter, samples: samples)
        #expect(storage.take().transactions == 1)
        let (_, again) = try await Fixtures.collect(exporter, samples: samples)
        #expect(storage.take() == (transactions: 1, writes: 0))
        receipt.release()
        again.release()
        #expect(storage.take().transactions == 1)
        let (_, empty) = try await Fixtures.collect(exporter, samples: [])
        empty.release()
        #expect(storage.take().transactions == 0)
    }

    @Test("G4: a changed symptom set or changed deletion bounds is a new event; two bounds in one call are two events")
    func recordPartsVersionTheEvent() async throws {
        let exporter = try Fixtures.exporter()
        let one = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0x81))
        let two = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0x82), type: .fatigue)
        let (single, _) = try await Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0x80, symptoms: [one])])
        let (same, _) = try await Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0x80, symptoms: [one])])
        let (pair, _) = try await Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0x80, symptoms: [two, one])])
        #expect(same[0].event == single[0].event)
        #expect(pair[0].event != single[0].event)
        #expect(pair.first { $0.source.uuid == one.uuid }?.event == single[1].event, "the unchanged symptom keeps its event")
        let before = try await Fixtures.retract(exporter, [Fixtures.deletion(0x83, deletedAfter: GoldenFixtures.sampleStart)])
        let after = try await Fixtures.retract(exporter, [Fixtures.deletion(0x83, deletedAfter: GoldenFixtures.sampleStart + 1)])
        #expect(before.retractions[0].event != after.retractions[0].event)
        let both = try await Fixtures.retract(exporter, [
            Fixtures.deletion(0x84, deletedAfter: GoldenFixtures.sampleStart),
            Fixtures.deletion(0x84, deletedAfter: nil),
            Fixtures.deletion(0x84, deletedAfter: GoldenFixtures.sampleStart)
        ])
        #expect(both.retractions[0].event != both.retractions[1].event)
        #expect(both.retractions[0].event == both.retractions[2].event)
        #expect(both.retractions[0].graph?.json != both.retractions[1].graph?.json)
    }

    @Test("G11: a released retraction forgets the deleted record's active reservation; an unreleased one forgets nothing")
    func retractionForgetsTheActiveKey() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x90))
        let key = try #require(ExchangeEventKey.active(sample))
        let (first, _) = try await Fixtures.collect(exporter, samples: [sample])
        _ = try await Fixtures.retract(exporter, [Fixtures.deletion(0x90)])
        #expect(try storage.holdsReservation(for: key), "a dropped retraction receipt forgets nothing")
        let (kept, _) = try await Fixtures.collect(exporter, samples: [sample])
        #expect(kept[0].event == first[0].event)
        let retraction = try await Fixtures.retract(exporter, [Fixtures.deletion(0x90)])
        retraction.receipt.release()
        #expect(try !storage.holdsReservation(for: key))
        let (renewed, _) = try await Fixtures.collect(exporter, samples: [sample])
        #expect(renewed[0].event != first[0].event)
    }

    @Test("E1: each ECG symptom maps to its own reservation by key, never by position")
    func symptomsPairByKey() async throws {
        let exporter = try Fixtures.exporter()
        let first = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA1))
        let last = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA3), type: .fatigue)
        let (paired, _) = try await Fixtures.collect(exporter, [try Fixtures.electrocardiogram(uuid: 0xA4, symptoms: [last, first])])
        let (standalone, _) = try await Fixtures.collect(exporter, samples: [first, last])
        try #require(paired.count == 3)
        #expect(paired.first { $0.source.uuid == first.uuid }?.graph?.json == standalone[0].graph?.json)
        #expect(paired.first { $0.source.uuid == last.uuid }?.graph?.json == standalone[1].graph?.json)
    }

    @Test(
        "E1: an unregistered symptom between two registered ones is refused as unsupported, the others keep their own requests",
        .enabled(if: HealthKitFHIRExporterLedgerTests.unregisteredCategoryType != nil, "no unregistered category type exists before OS 27")
    )
    func unregisteredSymptomIsRefusedAsSuch() async throws {
        let exporter = try Fixtures.exporter()
        let type = try #require(Self.unregisteredCategoryType)
        let first = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA1))
        let unregistered = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA2), type: type, value: 1)
        let last = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA3), type: .fatigue)
        #expect(HealthKitSourceType(unregistered) == nil)
        let input = try Fixtures.electrocardiogram(uuid: 0xA0, symptoms: [first, unregistered, last])
        let plan = HealthKitFHIRExporter.Plan(input, exporter: exporter)
        #expect(plan.symptoms.map { $0?.request.key } == [ExchangeEventKey.active(first), nil, ExchangeEventKey.active(last)])
        let (exports, _) = try await Fixtures.collect(exporter, [input])
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.unsupportedSymptomType(type.rawValue)))
    }

    @Test(
        "An unregistered sample is refused under its own identifier and reported under its own UUID and type identifier",
        .enabled(if: HealthKitFHIRExporterLedgerTests.unregisteredCategoryType != nil, "no unregistered category type exists before OS 27")
    )
    func unregisteredSampleIsRefusedUnderItsIdentifier() async throws {
        let type = try #require(Self.unregisteredCategoryType)
        let sample = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xA5), type: type, value: 1)
        let expected = HealthKitConversionError.unregisteredSourceType(type.rawValue)
        let (exports, _) = try await Fixtures.collect(try Fixtures.exporter(), samples: [sample])
        guard exports.count == 1, case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected one refusal, got \(exports.map(\.outcome))")
            return
        }
        #expect(reason == expected)
        // A type the inventory does not list has no source type to name, so the export reports the sample's UUID and
        // type identifier.
        #expect(exports[0].source.uuid == sample.uuid)
        #expect(exports[0].source.typeIdentifier == type.rawValue)
        #expect(exports[0].source.sourceType == nil)
    }

    /// The ledger holds every reservation under its key's digest, so a key part that changed would orphan them all.
    @Test("A record's active and retraction keys state the adapter token healthkit, its type and its lowercase UUID, a retraction also its bounds")
    func eventKeysStateTheirParts() throws {
        let record = "HKQuantityTypeIdentifierHeartRate|3a7e5c10-0000-4000-8000-0000000000c0"
        let active = ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: record)
        #expect(ExchangeEventKey.active(type: .heartRate, uuid: GoldenFixtures.uuid(0xC0)) == active)
        #expect(ExchangeEventKey.active(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC0))) == active)
        // The bounds in milliseconds since 1970, the unknown lower one empty.
        let bounded = ExchangeEventKey(kind: .retraction, adapterID: "healthkit", sourceRecord: record, revision: "1787005800000|1787009400000")
        #expect(ExchangeEventKey.retraction(Fixtures.deletion(0xC0, deletedAfter: GoldenFixtures.sampleStart)) == bounded)
        let unbounded = ExchangeEventKey(kind: .retraction, adapterID: "healthkit", sourceRecord: record, revision: "|1787009400000")
        #expect(ExchangeEventKey.retraction(Fixtures.deletion(0xC0)) == unbounded)
    }

    @Test("E2: an ECG through the records path takes one reserve, mints its symptoms' events, and redelivers byte-identically")
    func electrocardiogramThroughTheRecordsPath() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let symptom = try GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xB1))
        let input = try Fixtures.electrocardiogram(uuid: 0xB0, symptoms: [symptom])
        let (first, receipt) = try await Fixtures.collect(exporter, [input])
        #expect(storage.take().transactions == 1)
        try #require(first.count == 2)
        #expect(Set(first.compactMap(\.sequence)) == ["1", "2"])
        #expect(first[1].source.uuid == symptom.uuid)
        let (again, _) = try await Fixtures.collect(exporter, [input])
        #expect(again.map(\.graph?.json) == first.map(\.graph?.json))
        // A refused record holds its keys until the receipt is released.
        let refusedECG = try GoldenCase.electrocardiogramRecord(uuid: 0xB2, symptoms: [])
        let refusedKey = try #require(ExchangeEventKey.active(refusedECG.electrocardiogram))
        let (refused, refusedReceipt) = try await Fixtures.collect(exporter, [Fixtures.electrocardiogram(refusedECG, symptoms: [symptom])])
        guard case .refused = refused[0].outcome else {
            Issue.record("expected a refusal, got \(refused[0].outcome)")
            return
        }
        #expect(try storage.holdsReservation(for: refusedKey))
        refusedReceipt.release()
        #expect(try !storage.holdsReservation(for: refusedKey))
        receipt.release()
    }
}

#endif
