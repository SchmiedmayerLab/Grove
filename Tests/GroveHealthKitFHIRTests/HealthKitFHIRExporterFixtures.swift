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
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.retract(deletions, at: instant) { exports.append($0) }
        return (exports, receipt)
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

#endif
