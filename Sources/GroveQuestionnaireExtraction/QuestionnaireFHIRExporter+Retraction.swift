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
    /// A response to take back: the record exactly as it was exported, and when it was withdrawn.
    public struct Withdrawal: Sendable {
        /// The instrument and the response as they were exported; extracting them again names the Observations the
        /// retraction targets, so pass the same pair, not a later amendment of it.
        public let record: Record
        /// When the response stopped being exposed, as the retraction's `Provenance.occurred` states it.
        public let withdrawnAt: Date

        public init(record: Record, withdrawnAt: Date) {
            self.record = record
            self.withdrawnAt = withdrawnAt
        }
    }

    /// What one ``Withdrawal`` produced: a retraction graph, or the reason it produced none.
    public struct Retraction: Sendable {
        public enum Outcome: Sendable {
            /// The validated retraction graph; store or upload `ExchangeGraph.json` verbatim.
            case graph(ExchangeGraph)
            /// The withdrawal was refused; nothing was emitted and the retraction continued. A pair the export refused
            /// is refused here for the same reason, as it emitted nothing to take back.
            case refused(ObservationExtractionError)
        }

        /// The value of the response's business identifier, which names its source record; `nil` when it states none.
        public let responseIdentifier: String?
        public let outcome: Outcome

        /// The graph, when one was produced.
        public var graph: ExchangeGraph? {
            if case .graph(let graph) = outcome { graph } else { nil }
        }
    }

    /// Takes back withdrawn responses in input order, calling `receive` once per withdrawal with its retraction graph or
    /// its refusal.
    ///
    /// The graph states the guide's retraction path for a projected response: one source-record-retracted Provenance
    /// whose targets are the source-output identities of the Observations the export emitted, recomputed by extracting
    /// the pair again, so nothing from the export needs to be kept but the pair itself. Every retraction event is
    /// reserved in one ledger transaction, keyed by the response identifier and the withdrawal's millisecond, so an
    /// exact retry of the call before `ExchangeProducer.Receipt.release()` restates every event byte for byte, and a
    /// withdrawal reported again at another instant is another event. Releasing the receipt also forgets the response's
    /// active reservation, which no export will release once the response is gone. The call ends early for the same
    /// reasons as ``export(_:at:receive:)``.
    ///
    /// - Parameters:
    ///   - withdrawals: The responses to take back, each with the instrument it answers.
    ///   - instant: When the events are reserved; a redelivery before the receipt is released keeps the first one.
    ///   - receive: Called once per withdrawal, in input order.
    /// - Returns: The receipt to release once every graph is durably stored.
    public func retract(
        _ withdrawals: some Collection<Withdrawal>,
        at instant: Date = .now,
        receive: (Retraction) throws -> Void
    ) throws -> ExchangeProducer.Receipt {
        let plans = withdrawals.map { RetractionPlan($0, exporter: self) }
        let planned = plans.compactMap { try? $0.content.get() }
        // One fingerprint per key and call, the first in input order, as for an export.
        let firstPerKey = Dictionary(planned.map { ($0.request.key, $0.request) }) { first, _ in first }
        let (reserved, receipt) = try producer.reserve(
            Set(firstPerKey.values),
            at: instant,
            forgetting: planned.map { ExchangeEventKey.questionnaireResponse(.active, nativeRecordID: $0.extracted.nativeRecordID) }
        )
        for plan in plans {
            try receive(Retraction(responseIdentifier: plan.responseIdentifier, outcome: deliver(plan, reserved: reserved)))
        }
        return receipt
    }
}


extension QuestionnaireFHIRExporter {
    /// One withdrawal prepared before the reservation: the pair's extraction and the request its retraction reserves, or
    /// why it has none.
    struct RetractionPlan {
        struct Content {
            let extracted: ExtractedResponse
            let occurred: Date
            let request: ExchangeEventRequest
        }

        let responseIdentifier: String?
        let content: Result<Content, ObservationExtractionError>

        init(_ withdrawal: Withdrawal, exporter: QuestionnaireFHIRExporter) {
            self.responseIdentifier = withdrawal.record.response.identifier?.value?.value?.string
            do {
                let extracted = try ExtractedResponse(
                    questionnaire: withdrawal.record.questionnaire,
                    response: withdrawal.record.response,
                    identityScope: exporter.producer.identityScope,
                    repositoryScope: exporter.repositoryScope
                )
                let key = ExchangeEventKey.questionnaireResponse(
                    .retraction,
                    nativeRecordID: extracted.nativeRecordID,
                    revision: String(ExchangeInstant.millisecondsSinceEpoch(withdrawal.withdrawnAt))
                )
                // The pair names the targets, so another pair withdrawn at the same instant is another event.
                self.content = .success(Content(
                    extracted: extracted,
                    occurred: withdrawal.withdrawnAt,
                    request: exporter.context.request(for: key, recordParts: try Plan.recordParts(of: withdrawal.record))
                ))
            } catch {
                self.content = .failure(ObservationExtractionError(conversionFailure: error))
            }
        }
    }

    /// The planned withdrawal's retraction graph under its reservation, or why it has none. A refusal keeps its
    /// reservation held until the receipt is released, never mid-call.
    private func deliver(_ plan: RetractionPlan, reserved: [ExchangeEventRequest: ExchangeEventReservation]) -> Retraction.Outcome {
        let content: RetractionPlan.Content
        switch plan.content {
        case .failure(let refusal):
            return .refused(refusal)
        case .success(let planned):
            content = planned
        }
        guard let reservation = reserved[content.request] else {
            // An earlier withdrawal of this call names the same response at the same instant with another pair.
            return .refused(.conflictingDuplicate)
        }
        do {
            let context = ExchangeEventContext(
                subject: producer.subject,
                event: try ExchangeEventIdentifier(
                    system: producer.identityScope.systems.event,
                    producerInstance: reservation.producerInstance,
                    sequence: reservation.sequence
                ),
                identityScope: producer.identityScope,
                repositoryScope: repositoryScope,
                application: reservation.facts.application,
                host: reservation.facts.host,
                conversionInstant: reservation.instant,
                studies: reservation.facts.studies
            )
            let retraction = try RetractionEvent(
                targets: content.extracted.retractionTargets(),
                context: context,
                sourceRecord: content.extracted.sourceRecord.identifier,
                occurred: .instant(content.occurred)
            )
            return .graph(retraction.graph)
        } catch {
            return .refused(ObservationExtractionError(conversionFailure: error))
        }
    }
}


extension ExtractedResponse {
    /// What a retraction of this response names: each Observation its graph emits, a primary output under the
    /// source-output identity the graph minted for its measurement.
    func retractionTargets() throws -> [RetractionEvent.Target] {
        try measurements.map { measurement in
            try RetractionEvent.Target(
                identifier: sourceRecord.output(role: measurement.contract.id, discriminator: GraphFrame.outputDiscriminator),
                resourceType: .observation,
                role: .primaryOutput
            )
        }
    }
}


extension ExchangeEventKey {
    /// The key of a response's event of `kind` under the response identifier; a retraction's `revision` is the
    /// withdrawal's millisecond.
    static func questionnaireResponse(_ kind: ExchangeGraph.Kind, nativeRecordID: String, revision: String? = nil) -> ExchangeEventKey {
        ExchangeEventKey(
            kind: kind,
            adapterID: QuestionnaireExchangeProjection.adapterID,
            sourceRecord: "QuestionnaireResponse|\(nativeRecordID)",
            revision: revision
        )
    }
}
