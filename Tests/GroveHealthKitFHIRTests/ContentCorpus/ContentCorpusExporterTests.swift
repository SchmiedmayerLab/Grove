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


/// A sequencer ledger that starts where the corpus's events do: under the test context's producer instance, at
/// the corpus's sequence, so the exporter mints exactly the events the converter facade was handed.
private enum CorpusLedger {
    /// A sequencer over an in-memory ledger whose producer entry hands out `nextSequence` under `producerInstance`.
    ///
    /// Every corpus ledger states the same producer instance, so their reservation handles are not unique across
    /// ledgers; each sequencer therefore keeps its own hold registry instead of the process's shared one.
    static func sequencer(producerInstance: UUID, nextSequence: UInt64) throws -> ExchangeEventSequencer {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let producer = try ProducerEntry(instance: producerInstance, next: nextSequence).encoded()
        try storage.transaction { try $0.write(producer, for: LedgerKey.producer) }
        return ExchangeEventSequencer(storage: storage, holds: HoldRegistry())
    }
}


/// The exporter renders the corpus: every convert vector, exported through `HealthKitFHIRExporter` with the options
/// its converter context states and under the same events, produces the outputs, envelope digests and refusals
/// its line pins. The exporter reports a warning as its registered diagnostic only, so warnings compare by code.
///
/// This is where the corpus's port points lead: once the deprecated facade is gone, the recorder converts this way.
@Suite
struct ContentCorpusExporterTests {
    /// The test context every corpus event is minted under.
    private static let base = ExchangeEventContext.test()

    /// The tokens `source` exports to, warnings as codes; nil for a vector the exporter cannot state (an ECG whose
    /// symptom contexts the caller miscounts) or whose record this platform does not have.
    private static func exported(_ source: ContentCorpusSource) throws -> LosslessJSONValue? {
        let record: HealthKitFHIRExporter.Record
        do {
            guard let built = try exporterRecord(source) else {
                return nil
            }
            record = built
        } catch ContentCorpusSamples.RebuildError.unavailableHere {
            return nil
        }
        let exporter = try exporter(for: source)
        try reserveFacadeEvents(of: record, through: exporter)
        var exports: [HealthKitFHIRExporter.Export] = []
        _ = try exporter.export(records: [record], at: GoldenFixtures.conversionInstant) { exports.append($0) }
        guard !exports.isEmpty else {
            return .object(["omitted": .boolean(true)])
        }
        if exports.count == 1, case .refused(let error) = exports[0].outcome {
            return ContentCorpusRecorder.refusal(error)
        }
        let graphs = try exports.map { export in
            guard let graph = export.graph else {
                return LosslessJSONValue.string("unexpected outcome \(export.outcome)")
            }
            return try ContentCorpusRecorder.graph(graph, warnings: export.warnings.map(\.code))
        }
        return .object(["graphs": .array(graphs)])
    }

    /// Gives a record and its ECG symptoms the events the converter facade is handed for every vector that converts:
    /// the record the corpus's sequence, each symptom the next one in the record's order.
    ///
    /// The ledger numbers the new events of one call in the sorted order of their keys, which are digests, so an
    /// export that reserves an ECG and its symptoms together numbers them in no fixed order. Reserving each request
    /// on its own first, in the facade's order, numbers them as the facade does; the export then finds every
    /// reservation under its own request and reuses it.
    private static func reserveFacadeEvents(of record: HealthKitFHIRExporter.Record, through exporter: HealthKitFHIRExporter) throws {
        let requests = HealthKitFHIRExporter.Plan(record, exporter: exporter).requests
        guard requests.count > 1 else {
            return
        }
        for request in requests {
            _ = try exporter.producer.reserve([request], at: GoldenFixtures.conversionInstant)
        }
    }

    /// An exporter whose options state what `ContentCorpusRecorder.context(for:)` states for `source`.
    private static func exporter(for source: ContentCorpusSource) throws -> HealthKitFHIRExporter {
        let producer = try ExchangeProducer(
            identityScope: base.identityScope,
            subject: base.subject,
            application: base.application,
            host: base.host,
            studies: source.context == .linked ? [.test("study-a")] : [],
            sequencer: CorpusLedger.sequencer(producerInstance: base.event.producerInstance, nextSequence: ContentCorpusRecorder.sequence)
        )
        var options = HealthKitFHIRExporter.Options()
        if source.context == .linked {
            options.role = .gateway
        }
        if case .workoutRoute(_, disclosed: true) = source.record {
            options.route = .authorized
        }
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: base.repositoryScope, options: options)
    }

    /// The record the exporter takes for `source`, or nil for an ECG whose symptom contexts the vector miscounts.
    private static func exporterRecord(_ source: ContentCorpusSource) throws -> HealthKitFHIRExporter.Record? {
        switch source.record {
        case .electrocardiogram(let reading):
            guard reading.symptomContexts == nil else {
                return nil
            }
            let record = try ContentCorpusSamples.electrocardiogram(source, reading: reading)
            return .electrocardiogram(record.electrocardiogram, voltages: record.voltageMeasurements, symptoms: record.correlatedSymptoms)
        case .heartbeatSeries(let beats):
            let record = try ContentCorpusSamples.heartbeatSeries(source, beats: beats)
            return .heartbeatSeries(record.series, beats: record.heartbeats)
        case .workoutRoute(let locations, _):
            let record = try ContentCorpusSamples.workoutRoute(source, locations: locations)
            return .workoutRoute(record.route, locations: record.locations)
        default:
            return .sample(try ContentCorpusSamples.sample(source))
        }
    }

    /// A line's output with each rendered warning cut to its registry code, as the exporter reports it.
    private static func warningCodes(in output: LosslessJSONValue) -> LosslessJSONValue {
        guard case .object(var members) = output, let graphs = output["graphs"]?.elements else {
            return output
        }
        members["graphs"] = .array(graphs.map { graph in
            guard case .object(var graphMembers) = graph else {
                return graph
            }
            graphMembers["warnings"] = .array((graph["warnings"]?.elements ?? []).map { warning in
                .string(String((warning.text ?? "").prefix { $0 != "(" && $0 != "@" }))
            })
            return .object(graphMembers)
        })
        return .object(members)
    }

    /// Exports one shard's convert vectors and compares each with its line.
    @Test(.enabled(if: !ContentCorpusStore.isGenerating), arguments: 0..<ContentCorpusTests.shards)
    func exporterRendersEveryConvertLine(shard: Int) throws {
        var drifted: [String] = []
        var count = 0
        try ContentCorpusStore.forEachLine(in: ContentCorpusStore.checkedIn(), shard: (shard, ContentCorpusTests.shards)) { line in
            guard case .convert(let source) = line.input, let actual = try Self.exported(source) else {
                return
            }
            count += 1
            if let difference = TokenDiff.firstDifference(expected: Self.warningCodes(in: line.output), actual: actual) {
                drifted.append("\(line.id) at \(difference)")
            }
        }
        #expect(count > 0, "shard \(shard) of the corpus has no convert vector")
        #expect(drifted.isEmpty, "\(drifted.count) vectors export otherwise than the corpus pins: \(drifted.prefix(25))")
    }
}

#endif
