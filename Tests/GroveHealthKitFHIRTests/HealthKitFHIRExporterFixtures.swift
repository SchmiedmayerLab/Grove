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


/// Counts the ledger transactions and writes an exporter makes over an in-memory ledger.
final class LedgerCountingStorage: ExchangeProducer.Storage, @unchecked Sendable { // The counts are guarded by `lock`.
    private struct Counting: ExchangeProducer.Transaction {
        let base: any ExchangeProducer.Transaction
        let storage: LedgerCountingStorage

        func read(_ key: String) throws -> Data? {
            try base.read(key)
        }

        func write(_ value: Data, for key: String) throws {
            storage.countWrite()
            try base.write(value, for: key)
        }

        func remove(_ key: String) throws {
            storage.countWrite()
            try base.remove(key)
        }

        func keys(prefixedBy prefix: String) throws -> [String] {
            try base.keys(prefixedBy: prefix)
        }
    }

    let base = ExchangeProducer.InMemoryStorage()
    private let lock = NSLock()
    private var transactions = 0
    private var writes = 0

    /// Transactions and writes (removals included) since the last call, which starts a new tally.
    func take() -> (transactions: Int, writes: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }
        defer {
            (transactions, writes) = (0, 0)
        }
        return (transactions, writes)
    }

    func transaction<R>(_ body: (any ExchangeProducer.Transaction) throws -> R) throws -> R {
        lock.lock()
        transactions += 1
        lock.unlock()
        return try base.transaction { try body(Counting(base: $0, storage: self)) }
    }

    /// Whether the ledger holds a reservation for `key`.
    func holdsReservation(for key: ExchangeEventKey) throws -> Bool {
        try base.transaction { try $0.read(LedgerKey.event(key)) } != nil
    }

    private func countWrite() {
        lock.lock()
        defer {
            lock.unlock()
        }
        writes += 1
    }
}


/// What a test varies about one export besides its record: the producer's subject, application, host and studies,
/// the root of the identity systems, the call's instant, the event sequences, and the exporter's options.
struct ExportInputs: Sendable {
    /// The default inputs with every source classified as an application, for the tests that pin how a writer travels;
    /// by default no writer is stated.
    static var applicationWriter: ExportInputs {
        var inputs = ExportInputs()
        inputs.options.writer = .classify { _ in .application }
        return inputs
    }

    var subject: Subject = .testPatient
    var converter: ApplicationDevice = .test
    var converterHost: HostDevice = .test
    var studies: [StudyEnrollment] = []
    /// The root of the identity systems and the repository scope, as `ExchangeEventContext.test(graphIdentifierSystem:)`
    /// takes it.
    var graphIdentifierSystem: IdentifierSystem?
    var instant = GoldenFixtures.conversionInstant
    /// The record's event sequence; by default the instant in milliseconds, as `ExchangeEventContext.test` numbers it.
    var sequence: UInt64?
    /// Each ECG symptom's event sequence, in the record's order; a symptom without one takes the sequence after the
    /// previous event's.
    var symptomSequences: [UInt64] = []
    var options = HealthKitFHIRExporter.Options()

    /// The test context whose identity scope, repository scope and producer instance every export states.
    var base: ExchangeEventContext {
        .test(graphIdentifierSystem: graphIdentifierSystem)
    }

    /// The sequence the record's event takes.
    var recordSequence: UInt64 {
        sequence ?? UInt64(max(1, Int64(instant.timeIntervalSince1970 * 1_000)))
    }
}


/// Why a test's export produced no graph to read back.
enum ExportFixtureError: Error {
    /// The call delivered no export: a policy omitted the record.
    case nothingExported
    /// The deletion names no output the exporter can have emitted.
    case nothingToRetract
    /// The export carries no graph.
    case noGraph(HealthKitFHIRExporter.Export.Outcome)
}


/// Producers, exporters and records the exporter tests share.
enum ExporterFixtures {
    static let base = ExchangeEventContext.test()

    static func producer(
        identityScope: OpaqueIdentityScope = base.identityScope,
        subject: Subject = base.subject,
        application: ApplicationDevice = base.application,
        host: HostDevice = base.host,
        studies: [StudyEnrollment] = [],
        storage: any ExchangeProducer.Storage,
        holds: HoldRegistry = .shared
    ) throws -> ExchangeProducer {
        try ExchangeProducer(
            identityScope: identityScope,
            subject: subject,
            application: application,
            host: host,
            studies: studies,
            ledger: ExchangeProducer.Ledger(storage: storage, holds: holds)
        )
    }

    static func exporter(
        _ producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier = base.repositoryScope,
        revisions: HealthKitFHIRExporter.OutputRevisions = .current,
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }
    ) throws -> HealthKitFHIRExporter {
        var options = HealthKitFHIRExporter.Options()
        configure(&options)
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: repositoryScope, options: options, outputRevisions: revisions)
    }

    static func exporter(
        storage: any ExchangeProducer.Storage = ExchangeProducer.InMemoryStorage(),
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }
    ) throws -> HealthKitFHIRExporter {
        try exporter(producer(storage: storage), configure)
    }

    /// Every export of one call, and its receipt.
    static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ records: [HealthKitFHIRExporter.Record],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.export(records: records, at: instant) { exports.append($0) }
        return (exports, receipt)
    }

    static func collect(
        _ exporter: HealthKitFHIRExporter,
        samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        try collect(exporter, samples.map { .sample($0) }, at: instant)
    }

    static func retract(
        _ exporter: HealthKitFHIRExporter,
        _ deletions: [HealthKitFHIRExporter.Deletion],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (retractions: [HealthKitFHIRExporter.Retraction], receipt: ExchangeProducer.Receipt) {
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        let receipt = try exporter.retract(deletions, at: instant) { retractions.append($0) }
        return (retractions, receipt)
    }

    /// The goldens' ECG record with its correlated symptoms, which it states present exactly when there are any.
    static func electrocardiogram(uuid ordinal: UInt8, symptoms: [HKCategorySample]) throws -> HealthKitFHIRExporter.Record {
        try electrocardiogram(GoldenCase.electrocardiogramRecord(uuid: ordinal, symptoms: symptoms), symptoms: symptoms)
    }

    /// `record`'s ECG and voltages with `symptoms`, whatever symptoms status the ECG states.
    static func electrocardiogram(_ record: HealthKitECGRecord, symptoms: [HKCategorySample]) -> HealthKitFHIRExporter.Record {
        .electrocardiogram(record.electrocardiogram, voltages: record.voltageMeasurements, symptoms: symptoms)
    }

    static func deletion(_ ordinal: UInt8, deletedAfter: Date? = nil, detectedAt: Date = GoldenFixtures.conversionInstant) -> HealthKitFHIRExporter.Deletion {
        HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(ordinal), sourceType: .heartRate, deletedAfter: deletedAfter, detectedAt: detectedAt)
    }
}


extension ExporterFixtures {
    /// An exporter with `inputs`' facts and options over a fresh in-memory ledger that hands out the record's sequence
    /// next under the test context's producer instance. Every such ledger states that one instance, so each keeps its
    /// own hold registry: the process's shared one would see their reservations as one ledger's.
    static func exporter(_ inputs: ExportInputs) throws -> (exporter: HealthKitFHIRExporter, storage: ExchangeProducer.InMemoryStorage) {
        let storage = ExchangeProducer.InMemoryStorage()
        try setNextSequence(inputs.recordSequence, of: storage, inputs: inputs)
        let producer = try ExchangeProducer(
            identityScope: inputs.base.identityScope,
            subject: inputs.subject,
            application: inputs.converter,
            host: inputs.converterHost,
            studies: inputs.studies,
            ledger: ExchangeProducer.Ledger(storage: storage, holds: HoldRegistry())
        )
        let exporter = try HealthKitFHIRExporter(producer: producer, repositoryScope: inputs.base.repositoryScope, options: inputs.options)
        return (exporter, storage)
    }

    /// Every export one call delivers for `record`, its events numbered as `inputs` states: the record's event takes
    /// ``ExportInputs/recordSequence`` and each ECG symptom's the next of ``ExportInputs/symptomSequences``.
    ///
    /// The ledger numbers the new events of one call in the sorted order of their keys, which are digests, so an ECG
    /// and its symptoms reserved together take their sequences in no fixed order. Reserving each request on its own
    /// first, in the record's order, numbers them as stated; the export then finds every reservation under its own
    /// request and reuses it.
    static func exports(_ record: HealthKitFHIRExporter.Record, _ inputs: ExportInputs = ExportInputs()) throws -> [HealthKitFHIRExporter.Export] {
        let (exporter, storage) = try exporter(inputs)
        let requests = HealthKitFHIRExporter.Plan(record, exporter: exporter).requests
        if requests.count > 1 {
            var sequence = inputs.recordSequence
            for (index, request) in requests.enumerated() {
                if index > 0 {
                    sequence = index <= inputs.symptomSequences.count ? inputs.symptomSequences[index - 1] : sequence + 1
                }
                try setNextSequence(sequence, of: storage, inputs: inputs)
                _ = try exporter.producer.reserve([request], at: inputs.instant)
            }
        }
        var exports: [HealthKitFHIRExporter.Export] = []
        _ = try exporter.export(records: [record], at: inputs.instant) { exports.append($0) }
        return exports
    }

    /// Every graph one call exports for `record`, read back; a refusal is thrown as the exporter reported it.
    static func export(_ record: HealthKitFHIRExporter.Record, _ inputs: ExportInputs = ExportInputs()) throws -> ExportedRecord {
        try ExportedRecord(exports(record, inputs))
    }

    /// Every graph one call exports for `sample`, read back; a refusal is thrown as the exporter reported it.
    static func export(_ sample: HKSample, _ inputs: ExportInputs = ExportInputs()) throws -> ExportedRecord {
        try export(.sample(sample), inputs)
    }

    /// The retraction graph of `deletion` under `inputs`, its event numbered ``ExportInputs/recordSequence``; a refusal is
    /// thrown as the exporter reported it.
    static func retraction(_ deletion: HealthKitFHIRExporter.Deletion, _ inputs: ExportInputs = ExportInputs()) throws -> ExchangeGraph {
        let (exporter, _) = try exporter(inputs)
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        _ = try exporter.retract([deletion], at: inputs.instant) { retractions.append($0) }
        guard let retraction = retractions.first else {
            throw ExportFixtureError.nothingExported
        }
        switch retraction.outcome {
        case .graph(let graph):
            return graph
        case .refused(let error):
            throw error
        case .nothingToRetract:
            throw ExportFixtureError.nothingToRetract
        }
    }

    /// Every graph `record` exports to on its own under `inputs`' facts and options, through a fresh ledger that hands
    /// out exactly `event`: what a call delivers for a record states nothing of the call's other records.
    static func standalone(
        _ record: HealthKitFHIRExporter.Record,
        as event: ExchangeEventIdentifier?,
        _ inputs: ExportInputs = ExportInputs()
    ) throws -> ExportedRecord {
        let (exporter, storage) = try exporter(inputs)
        try handOut(try #require(event), from: storage)
        return try ExportedRecord(collect(exporter, [record], at: inputs.instant).exports)
    }

    /// The retraction graph `deletion` takes on its own, through a fresh ledger that hands out exactly `event`.
    static func standalone(_ deletion: HealthKitFHIRExporter.Deletion, as event: ExchangeEventIdentifier?) throws -> ExchangeGraph? {
        let (exporter, storage) = try exporter(ExportInputs())
        try handOut(try #require(event), from: storage)
        return try retract(exporter, [deletion], at: deletion.detectedAt).retractions.first?.graph
    }

    /// Makes the ledger behind `storage` hand out `sequence` next under the test context's producer instance.
    private static func setNextSequence(_ sequence: UInt64, of storage: ExchangeProducer.InMemoryStorage, inputs: ExportInputs) throws {
        let entry = try ProducerEntry(instance: inputs.base.event.producerInstance, next: sequence).encoded()
        try storage.transaction { try $0.write(entry, for: LedgerKey.producer) }
    }

    /// Makes the ledger behind `storage` hand out `event` next.
    private static func handOut(_ event: ExchangeEventIdentifier, from storage: ExchangeProducer.InMemoryStorage) throws {
        let entry = try ProducerEntry(instance: event.producerInstance, next: #require(UInt64(event.sequence.rawValue))).encoded()
        try storage.transaction { try $0.write(entry, for: LedgerKey.producer) }
    }
}


extension HealthKitFHIRExporter.Export {
    /// The graph's event identifier.
    var event: ExchangeEventIdentifier? {
        graph?.eventIdentifier
    }

    /// The graph's event sequence.
    var sequence: String? {
        graph?.eventIdentifier.sequence.rawValue
    }
}


extension HealthKitFHIRExporter.Retraction {
    /// The graph's event identifier.
    var event: ExchangeEventIdentifier? {
        graph?.eventIdentifier
    }

    /// The graph's event sequence.
    var sequence: String? {
        graph?.eventIdentifier.sequence.rawValue
    }
}

#endif
