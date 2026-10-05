//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// Retracts deleted records in input order, calling `receive` once per deletion: one retraction event per deletion
    /// that names outputs this exporter can have emitted; every other deletion is reported as
    /// ``Retraction/Outcome/nothingToRetract``. Targets are recomputed from the catalog, so nothing from the original
    /// export needs to be kept.
    ///
    /// Every retraction event is reserved in one ledger transaction. Two deletions of one record with
    /// different bounds are two events, each under its own key, so an exact retry of the call reproduces
    /// both; a deletion reported again with other bounds is another event, and the reservation of the
    /// earlier bounds stays until its own receipt is released. Releasing the receipt also forgets each
    /// deleted record's active reservation, which no export will release once the record is gone: one the
    /// same ledger generation made, never one from after a `resetLedger()`, and one a live export still holds
    /// only once that export finishes. A call with nothing to retract forgets nothing. The call ends early
    /// for the same reasons as ``export(_:at:receive:)``: an unstatable `instant`, a `LedgerError`
    /// (recovered by `ExchangeProducer.resetLedger()`), and errors of the ledger's storage or of `receive`.
    public func retract(
        _ deletions: some Collection<Deletion>,
        at instant: Date = .now,
        receive: (Retraction) throws -> Void
    ) throws -> ExchangeProducer.Receipt {
        let requests = deletions.map { deletion in
            isRetractable(deletion) ? context.request(for: .retraction(deletion)) : nil
        }
        let (reserved, receipt) = try producer.reserve(
            Set(requests.compactMap(\.self)),
            at: instant,
            forgetting: deletions.map { ExchangeEventKey.active(type: $0.sourceType, uuid: $0.uuid) }
        )
        for (deletion, request) in zip(deletions, requests) {
            guard let request, let reservation = reserved[request] else {
                try receive(Retraction(deletion: deletion, outcome: .nothingToRetract))
                continue
            }
            // A refusal keeps its reservation held until the receipt is released, never mid-call.
            let outcome: Retraction.Outcome
            do {
                outcome = .graph(try retraction(of: deletion, reservation: reservation))
            } catch {
                outcome = .refused(HealthKitConversionError(conversionFailure: error, source: deletion.sourceType))
            }
            try receive(Retraction(deletion: deletion, outcome: outcome))
        }
        return receipt
    }

    /// Whether a deletion names outputs this exporter can have emitted. A type without outputs never emitted any,
    /// and a workout route is exported only under ``Options/route`` `.authorized`: retracting an undisclosed route
    /// would name a node that never existed and disclose that the route did.
    private func isRetractable(_ deletion: Deletion) -> Bool {
        guard !HealthKitContentPlan[deletion.sourceType].outputs.isEmpty else {
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
            repositoryIDs: try legacyRepositoryIDs(for: deletion.uuid)
        )
        let occurred = RetractionOccurrence.period(start: deletion.clampedDeletedAfter, end: deletion.detectedAt)
        return try assembly.retraction(of: deletion.uuid, type: deletion.sourceType, request: request, occurred: occurred).graph
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Deletion {
    /// The lower bound the retraction states. A backwards clock adjustment can put the earlier query after
    /// the detection; the known upper bound is kept rather than an invalid period stated.
    var clampedDeletedAfter: Date? {
        deletedAfter.flatMap { $0 <= detectedAt ? $0 : nil }
    }

    /// The bounds the retraction states, in milliseconds; the lower one is empty when unknown.
    var occurrenceParts: [String] {
        [
            clampedDeletedAfter.map { String(ExchangeInstant.millisecondsSinceEpoch($0)) } ?? "",
            String(ExchangeInstant.millisecondsSinceEpoch(detectedAt))
        ]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeEventKey {
    /// The retraction-event key of a deletion: the source type and UUID under the retraction kind, with the bounds
    /// the retraction states as its revision, so each reported occurrence keeps a reservation of its own.
    static func retraction(_ deletion: HealthKitFHIRExporter.Deletion) -> ExchangeEventKey {
        ExchangeEventKey(
            kind: .retraction,
            adapterID: HealthKitAssembly.adapter.adapterID,
            sourceRecord: "\(deletion.sourceType.rawValue)|\(deletion.uuid.uuidString.lowercased())",
            // Decimal milliseconds or empty, so the separator is unambiguous.
            revision: deletion.occurrenceParts.joined(separator: "|")
        )
    }
}

#endif
