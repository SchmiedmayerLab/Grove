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
    /// Errors from the sequencer's storage and from `receive` end the call.
    public func retract(
        _ deletions: some Collection<Deletion>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> Receipt {
        let keys = deletions.filter(isRetractable).map(ExchangeEventKey.retraction)
        var reservations = (keys.isEmpty ? [] : try producer.sequencer.reserve(keys, at: instant)).makeIterator()
        let producerInstance = keys.isEmpty ? UUID() : try producer.sequencer.producerInstance
        for deletion in deletions {
            guard isRetractable(deletion), let reservation = reservations.next() else {
                try receive(Export(source: deletion.source, outcome: .nothingToRetract, warnings: []))
                continue
            }
            let outcome: Export.Outcome
            do {
                outcome = .graph(try retraction(of: deletion, reservation: reservation, producerInstance: producerInstance))
            } catch {
                producer.sequencer.releaseIgnoringErrors([ExchangeEventKey.retraction(deletion)])
                outcome = .refused(HealthKitConversionError(conversionFailure: error, source: deletion.sourceType))
            }
            try receive(Export(source: deletion.source, outcome: outcome, warnings: []))
        }
        return Receipt(keys: keys, sequencer: producer.sequencer)
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

    private func retraction(
        of deletion: Deletion,
        reservation: ExchangeEventReservation,
        producerInstance: UUID
    ) throws -> ExchangeGraph {
        let request = HealthKitAssembly.Request(
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: producerInstance,
                sequence: reservation.sequence
            ),
            instant: reservation.instant,
            repositoryIDs: try legacyRepositoryIDs(for: deletion.uuid),
            options: HealthKitConversionOptions(nativeIdentifierDisclosure: options.nativeIdentifier)
        )
        let record = HealthKitSourceRecord(uuid: deletion.uuid, type: deletion.sourceType)
        // A backwards clock adjustment can put the earlier query after the detection; keep the known
        // upper bound rather than stating an invalid period.
        let occurred = RetractionOccurrence.period(
            start: deletion.deletedAfter.flatMap { $0 <= deletion.detectedAt ? $0 : nil },
            end: deletion.detectedAt
        )
        return try assembly.retraction(of: record, request: request, occurred: occurred).graph
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Deletion {
    var source: HealthKitFHIRExporter.Export.Source {
        HealthKitFHIRExporter.Export.Source(uuid: uuid, typeIdentifier: sourceType.rawValue)
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
