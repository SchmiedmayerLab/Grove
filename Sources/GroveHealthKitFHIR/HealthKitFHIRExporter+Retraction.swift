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
    /// Retracts deleted records in input order, calling `receive` once per deletion: one retraction record per deletion
    /// that names outputs this exporter can have emitted; every other deletion is reported as
    /// ``Retraction/Outcome/nothingToRetract``. A retraction's one target is the source record, recomputed from the
    /// deletion's coordinates, so nothing from the original export needs to be kept.
    ///
    /// The call ends early for the same reasons as ``export(_:at:receive:)``: an unstatable `instant`, errors of `receive`,
    /// and cancellation before the next records are handed over.
    nonisolated(nonsending) public func retract(
        _ deletions: some Collection<Deletion>,
        at instant: Date = .now,
        receive: (Retraction) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil else {
            throw ExchangeIdentityError.invalidInstant
        }
        try await ConcurrentBuild.forEach(Array(deletions), width: options.maximumConcurrency ?? ConcurrentBuild.defaultWidth) { deletion in
            self.outcome(of: deletion, at: instant)
        } hand: { deletion, outcome in
            try receive(Retraction(deletion: deletion, outcome: outcome))
        }
    }

    /// The outcome of one deletion: nothing to retract, else its retraction record or why it has none.
    private func outcome(of deletion: Deletion, at instant: Date) -> Retraction.Outcome {
        guard isRetractable(deletion) else {
            return .nothingToRetract
        }
        do {
            return .record(try retraction(of: deletion, at: instant))
        } catch {
            return .refused(HealthKitConversionError(conversionFailure: error, source: deletion.sourceType))
        }
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

    private func retraction(of deletion: Deletion, at instant: Date) throws -> ExchangeRecord {
        let request = HealthKitAssembly.Request(instant: instant, facts: producer.facts)
        let occurred = RetractionRecord.Occurrence.period(start: deletion.clampedDeletedAfter, end: deletion.detectedAt)
        return try assembly.retraction(of: deletion.uuid, type: deletion.sourceType, request: request, occurred: occurred).record
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Deletion {
    /// The lower bound the retraction states. A backwards clock adjustment can put the earlier query after
    /// the detection; the known upper bound is kept rather than an invalid period stated.
    var clampedDeletedAfter: Date? {
        deletedAfter.flatMap { $0 <= detectedAt ? $0 : nil }
    }
}

#endif
