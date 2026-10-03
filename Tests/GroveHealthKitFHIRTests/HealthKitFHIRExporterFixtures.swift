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
final class LedgerCountingStorage: ExchangeEventSequencer.Storage, @unchecked Sendable { // The counts are guarded by `lock`.
    private struct Counting: ExchangeEventSequencer.Transaction {
        let base: any ExchangeEventSequencer.Transaction
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

    let base = ExchangeEventSequencer.InMemoryStorage()
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

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
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
        sequencer: ExchangeEventSequencer
    ) throws -> ExchangeProducer {
        try ExchangeProducer(
            identityScope: identityScope,
            subject: subject,
            application: application,
            host: host,
            studies: studies,
            sequencer: sequencer
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
        sequencer: ExchangeEventSequencer = .inMemory(),
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }
    ) throws -> HealthKitFHIRExporter {
        try exporter(producer(sequencer: sequencer), configure)
    }

    /// Every export of one call, and its receipt.
    static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ inputs: [HealthKitFHIRExporter.Input],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: HealthKitFHIRExporter.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.export(inputs: inputs, at: instant) { exports.append($0) }
        return (exports, receipt)
    }

    static func collect(
        _ exporter: HealthKitFHIRExporter,
        samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: HealthKitFHIRExporter.Receipt) {
        try collect(exporter, samples.map { .record(.sample($0)) }, at: instant)
    }

    static func retract(
        _ exporter: HealthKitFHIRExporter,
        _ deletions: [HealthKitFHIRExporter.Deletion],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: HealthKitFHIRExporter.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.retract(deletions, at: instant) { exports.append($0) }
        return (exports, receipt)
    }

    /// An ECG with prebuilt evidence and its correlated symptoms, through the exporter's internal seam.
    static func electrocardiogram(uuid ordinal: UInt8, symptoms: [HKCategorySample]) throws -> HealthKitFHIRExporter.Input {
        let (ecg, evidence) = try GoldenCase.electrocardiogramEvidence(uuid: ordinal, symptomsPresent: !symptoms.isEmpty)
        return .electrocardiogramEvidence(ecg, evidence: evidence, symptoms: symptoms)
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
