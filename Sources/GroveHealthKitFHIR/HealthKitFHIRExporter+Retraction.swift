//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
import GroveFHIRContract
import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// Retracts deleted records in input order, one retraction event per deletion that names outputs this
    /// exporter can have emitted; every other deletion is reported as ``Export/Outcome/nothingToRetract``.
    /// Targets are recomputed from the catalog, so nothing from the original export needs to be kept.
    ///
    /// Every retraction event is reserved in one ledger transaction. Two deletions of one record with
    /// different bounds are two events. Releasing the receipt also forgets each deleted record's active
    /// reservation, which no export will release once the record is gone. Errors from the sequencer's
    /// storage and from `receive` end the call.
    public func retract(
        _ deletions: some Collection<Deletion>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> Receipt {
        let requests = deletions.map { deletion in
            isRetractable(deletion) ? context.request(for: .retraction(deletion), recordParts: deletion.occurrenceParts) : nil
        }
        let unique = Set(requests.compactMap(\.self))
        let reserved = unique.isEmpty ? [:] : try producer.sequencer.reserve(unique, at: instant, facts: producer.facts)
        // Created before any delivery: when a delivery throws, the receipt is dropped and its holds lapse.
        let receipt = Receipt(
            sequencer: producer.sequencer,
            held: reserved.values.map(\.handle),
            forgetting: deletions.map { ExchangeEventKey.active(type: $0.sourceType, uuid: $0.uuid) }
        )
        for (deletion, request) in zip(deletions, requests) {
            guard let request, let reservation = reserved[request] else {
                try receive(Export(source: deletion.source, outcome: .nothingToRetract, warnings: []))
                continue
            }
            // A refusal keeps its reservation held until the receipt is released, never mid-call.
            let outcome: Export.Outcome
            do {
                outcome = .graph(try retraction(of: deletion, reservation: reservation))
            } catch {
                outcome = .refused(HealthKitConversionError(conversionFailure: error, source: deletion.sourceType))
            }
            try receive(Export(source: deletion.source, outcome: outcome, warnings: []))
        }
        return receipt
    }

    /// Whether a deletion names outputs this exporter can have emitted. A type without outputs never emitted any,
    /// and a workout route is exported only under ``Options/route`` `.authorized`: retracting an undisclosed route
    /// would name a node that never existed and disclose that the route did.
    private func isRetractable(_ deletion: Deletion) -> Bool {
        guard !HealthKitCatalog.outputs(for: deletion.sourceType).isEmpty else {
            return false
        }
        return deletion.sourceType != .workoutRoute || options.route == .authorized
    }

    private func retraction(of deletion: Deletion, reservation: ExchangeEventReservation) throws -> ExchangeGraph {
        let request = HealthKitAssembly.Request(
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: reservation.producerInstance,
                sequence: reservation.sequence
            ),
            instant: reservation.instant,
            facts: reservation.facts,
            repositoryIDs: try legacyRepositoryIDs(for: deletion.uuid),
            options: HealthKitConversionOptions(nativeIdentifierDisclosure: options.nativeIdentifier)
        )
        let record = HealthKitSourceRecord(uuid: deletion.uuid, type: deletion.sourceType)
        let occurred = RetractionOccurrence.period(start: deletion.clampedDeletedAfter, end: deletion.detectedAt)
        return try assembly.retraction(of: record, request: request, occurred: occurred).graph
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Deletion {
    var source: HealthKitFHIRExporter.Export.Source {
        HealthKitFHIRExporter.Export.Source(uuid: uuid, typeIdentifier: sourceType.rawValue)
    }

    /// The lower bound the retraction states. A backwards clock adjustment can put the earlier query after
    /// the detection; the known upper bound is kept rather than an invalid period stated.
    var clampedDeletedAfter: Date? {
        deletedAfter.flatMap { $0 <= detectedAt ? $0 : nil }
    }

    /// What the retraction key does not version but the graph states: the bounds, in milliseconds.
    var occurrenceParts: [String] {
        [
            clampedDeletedAfter.map { String(ExchangeInstant.millisecondsSinceEpoch($0)) } ?? "",
            String(ExchangeInstant.millisecondsSinceEpoch(detectedAt))
        ]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeEventKey {
    /// The retraction-event key of a deletion: the source type and UUID under the retraction kind.
    static func retraction(_ deletion: HealthKitFHIRExporter.Deletion) -> ExchangeEventKey {
        ExchangeEventKey(
            kind: .retraction,
            adapterID: HealthKitConverter.adapterID,
            sourceRecord: "\(deletion.sourceType.rawValue)|\(deletion.uuid.uuidString.lowercased())"
        )
    }
}

#endif
