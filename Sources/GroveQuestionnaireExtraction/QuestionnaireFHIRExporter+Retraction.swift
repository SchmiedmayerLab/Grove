//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


extension QuestionnaireFHIRExporter {
    /// A response to take back, and when it was withdrawn.
    public struct Withdrawal: Sendable {
        /// The instrument and the response. Extracting them names the Observations the retraction lists; the retraction
        /// withdraws the whole response record whatever they name.
        public let record: Record
        /// When the response stopped being exposed, as the retraction's `Provenance.occurred` states it.
        public let withdrawnAt: Date

        public init(record: Record, withdrawnAt: Date) {
            self.record = record
            self.withdrawnAt = withdrawnAt
        }
    }

    /// What one ``Withdrawal`` produced: a retraction record, or the reason it produced none.
    public struct Retraction: Sendable {
        public enum Outcome: Sendable {
            /// The validated retraction record; pack it into a retraction Bundle for upload.
            case record(ExchangeRecord)
            /// The withdrawal was refused; nothing was emitted and the retraction continued. A pair the export refused
            /// is refused here for the same reason, as it emitted nothing to take back.
            case refused(ObservationExtractionError)
        }

        /// The value of the response's business identifier, which names its source record; `nil` when it states none.
        public let responseIdentifier: String?
        public let outcome: Outcome

        /// The record, when one was produced.
        public var record: ExchangeRecord? {
            if case .record(let record) = outcome { record } else { nil }
        }
    }

    /// Takes back withdrawn responses in input order, calling `receive` once per withdrawal with its retraction record or
    /// its refusal.
    ///
    /// The record states the guide's retraction path for a projected response: one source-record-retracted Provenance
    /// that withdraws the whole response, whose targets are the source-output identities of the Observations the export
    /// emitted, recomputed by extracting the pair again. The call ends early for the same reasons as
    /// ``export(_:at:receive:)``.
    ///
    /// - Parameters:
    ///   - withdrawals: The responses to take back, each with the instrument it answers.
    ///   - instant: When the assertion is recorded.
    ///   - receive: Called once per withdrawal, in input order.
    nonisolated(nonsending) public func retract(
        _ withdrawals: some Collection<Withdrawal>,
        at instant: Date = .now,
        receive: (Retraction) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil else {
            throw ExchangeIdentityError.invalidInstant
        }
        for withdrawal in withdrawals {
            let responseIdentifier = withdrawal.record.response.identifier?.value?.value?.string
            try receive(Retraction(responseIdentifier: responseIdentifier, outcome: outcome(of: withdrawal, at: instant)))
        }
    }
}


extension QuestionnaireFHIRExporter {
    /// The withdrawal's retraction record, or why it has none.
    private func outcome(of withdrawal: Withdrawal, at instant: Date) -> Retraction.Outcome {
        do {
            let extracted = try extraction(of: withdrawal.record)
            let scope = ExchangeEnvelope.Scope(
                adapter: QuestionnaireExchangeProjection.adapter,
                identityScope: producer.identityScope,
                subject: producer.subject,
                repositoryScope: repositoryScope
            )
            let retraction = try ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: producer.facts)).retraction(
                of: extracted.sourceRecord.identifier,
                targets: extracted.retractionTargets(),
                occurred: .instant(withdrawal.withdrawnAt),
                at: instant
            )
            return .record(retraction.record)
        } catch {
            return .refused(ObservationExtractionError(conversionFailure: error))
        }
    }
}


extension ExtractedResponse {
    /// What a retraction of this response names: each Observation its record emits, a primary output under the
    /// source-output identity the record minted for its measurement.
    func retractionTargets() throws -> [RetractionRecord.Target] {
        try measurements.map { measurement in
            try RetractionRecord.Target(
                identifier: sourceRecord.output(role: measurement.contract.id, discriminator: GraphFrame.outputDiscriminator),
                resourceType: .observation,
                role: .primaryOutput
            )
        }
    }
}
