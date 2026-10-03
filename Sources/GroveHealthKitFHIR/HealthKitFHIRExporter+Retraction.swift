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
    /// Retracts deleted records in input order, one retraction event per deletion whose source type
    /// ever emits outputs. Targets are recomputed from the catalog, so nothing from the original
    /// export needs to be kept. Errors from the sequencer's storage and from `receive` end the call.
    public func retract(
        _ deletions: some Collection<Deletion>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> Receipt {
        let retractable = deletions.filter { !HealthKitCatalog.outputs(for: $0.sourceType).isEmpty }
        let keys = retractable.map(ExchangeEventKey.retraction)
        let reservations = try producer.sequencer.reserve(keys, at: instant)
        let producerInstance = try producer.sequencer.producerInstance
        for deletion in deletions where HealthKitCatalog.outputs(for: deletion.sourceType).isEmpty {
            try receive(Export(source: deletion.source, outcome: .nothingToRetract, warnings: []))
        }
        for (deletion, reservation) in zip(retractable, reservations) {
            let outcome: Export.Outcome
            do {
                outcome = .graph(try retraction(of: deletion, reservation: reservation, producerInstance: producerInstance))
            } catch {
                producer.sequencer.releaseIgnoringErrors([ExchangeEventKey.retraction(deletion)])
                outcome = .refused(HealthKitConversionError(conversionFailure: error, source: deletion.sourceType).diagnostic)
            }
            try receive(Export(source: deletion.source, outcome: outcome, warnings: []))
        }
        return Receipt(keys: keys, sequencer: producer.sequencer)
    }

    private func retraction(
        of deletion: Deletion,
        reservation: ExchangeEventReservation,
        producerInstance: UUID
    ) throws -> ExchangeGraph {
        let event = ExchangeEventContext(
            subject: producer.subject,
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: producerInstance,
                sequence: reservation.sequence
            ),
            identityScope: producer.identityScope,
            repositoryScope: repositoryScope,
            application: producer.application,
            host: producer.host,
            conversionInstant: reservation.instant,
            converterRole: .assembler,
            studies: producer.studies,
            repositoryIDs: [:]
        )
        let context = HealthKitConversionContext(
            event: event,
            options: HealthKitConversionOptions(nativeIdentifierDisclosure: options.nativeIdentifier)
        )
        let record = HealthKitSourceRecord(uuid: deletion.uuid, type: deletion.sourceType)
        let occurred = RetractionOccurrence.period(
            start: deletion.deletedAfter.map { min($0, deletion.detectedAt) },
            end: deletion.detectedAt
        )
        return try HealthKitConverter.retraction(for: record, context: context, occurred: occurred).graph
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
