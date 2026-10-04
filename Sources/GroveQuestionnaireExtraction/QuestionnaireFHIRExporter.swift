//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Turns completed QuestionnaireResponses into exchange graphs for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share across tasks.
/// Every export mints its events through the producer, in one ledger transaction per call, so an exact redelivery
/// before `ExchangeProducer.Receipt.release()` reproduces the same events byte for byte, even when the studies changed
/// in between. A response that cannot be projected is reported as a refusal instead of ending the call.
///
/// Each graph is the projection the questionnaire guide's worked example documents: the Patient, the response, the
/// application and host snapshots of the writer the response's writer context names, one Observation per extracted
/// measurement and the conversion Provenance, plus the study context when the producer knows the participant's
/// enrollments. The Patient is the producer's subject: the Patient it bundles, or one stating only the pseudonym. The
/// producer's application and host are frozen with each event as for every adapter, but a Questionnaire graph states
/// the writer instead.
public final class QuestionnaireFHIRExporter: Sendable {
    /// One instrument and a response to it.
    public struct Record: Sendable {
        let questionnaire: ModelsR4.Questionnaire
        let response: ModelsR4.QuestionnaireResponse

        public init(questionnaire: ModelsR4.Questionnaire, response: ModelsR4.QuestionnaireResponse) {
            self.questionnaire = questionnaire
            self.response = response
        }
    }

    /// What one record produced: an exchange graph, or the reason it produced none.
    public struct Export: Sendable {
        public enum Outcome: Sendable {
            /// The validated graph; store or upload `ExchangeGraph.json` verbatim.
            case graph(ExchangeGraph)
            /// The record was refused; nothing was emitted and the export continued. Refusals are deterministic,
            /// so an exact redelivery refuses identically.
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

    let producer: ExchangeProducer
    /// The business identifier naming the store the responses come from; it enters every source identity.
    let repositoryScope: BusinessIdentifier
    /// What shapes every graph beside the frozen facts and the record; it fingerprints each request.
    let context: ExchangeRequestContext

    /// Creates the exporter of one installation's questionnaire responses.
    ///
    /// - Parameters:
    ///   - producer: The producer whose ledger numbers every event and freezes the studies each one states.
    ///   - repositoryScope: The business identifier naming the store the responses come from; it enters every source
    ///     identity.
    public init(producer: ExchangeProducer, repositoryScope: BusinessIdentifier) {
        self.producer = producer
        self.repositoryScope = repositoryScope
        self.context = ExchangeRequestContext(
            label: "grove-questionnaire-context-v0",
            outputRevisions: [ExchangeGraphAssembler.outputRevision, QuestionnaireExchangeProjection.outputRevision],
            producer: producer,
            repositoryScope: repositoryScope,
            settings: []
        )
    }

    /// Projects records in input order, calling `receive` once per record with its graph or its refusal.
    ///
    /// A record that cannot be projected is refused in place, and so is a response the call names again with other
    /// content (``ObservationExtractionError/conflictingDuplicate``): the first input of a response keeps its event, so
    /// an exact retry of the call reproduces every event. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant` before the ledger is touched;
    /// - the producer's ledger throws `ExchangeProducer.LedgerError` when a stored entry is corrupt or from a later
    ///   layout, and `ExchangeProducer.resetLedger()` always recovers;
    /// - errors of the ledger's storage and of `receive` are rethrown unchanged, and the reservations made stay for
    ///   the redelivery.
    ///
    /// - Parameters:
    ///   - records: The responses to project, each with the instrument it answers.
    ///   - instant: When the events are reserved; a redelivery before the receipt is released keeps the first one.
    ///   - receive: Called once per record, in input order.
    /// - Returns: The receipt to release once every graph is durably stored.
    public func export(
        _ records: some Collection<Record>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> ExchangeProducer.Receipt {
        let plans = records.map { Plan($0, exporter: self) }
        // One fingerprint per key and call, the first in input order: a key reserved under two would keep only the
        // later, and a retry of the call would mint both again.
        let firstPerKey = Dictionary(plans.compactMap { try? $0.content.get().request }.map { ($0.key, $0) }) { first, _ in first }
        // Refusals alone need no event, and a call that reserves nothing never touches the ledger.
        let (reserved, receipt) = try producer.reserve(Set(firstPerKey.values), at: instant)
        for plan in plans {
            try receive(Export(responseIdentifier: plan.responseIdentifier, outcome: deliver(plan, reserved: reserved)))
        }
        return receipt
    }
}


extension QuestionnaireFHIRExporter {
    /// One record prepared before the reservation: its extraction and the request it reserves, or why it has none.
    struct Plan {
        struct Content {
            let extracted: ExtractedResponse
            let request: ExchangeEventRequest
        }

        let responseIdentifier: String?
        let content: Result<Content, ObservationExtractionError>

        init(_ record: Record, exporter: QuestionnaireFHIRExporter) {
            self.responseIdentifier = record.response.identifier?.value?.value?.string
            do {
                let extracted = try ExtractedResponse(
                    questionnaire: record.questionnaire,
                    response: record.response,
                    identityScope: exporter.producer.identityScope,
                    repositoryScope: exporter.repositoryScope
                )
                let key = ExchangeEventKey(
                    kind: .active,
                    adapterID: QuestionnaireExchangeProjection.adapterID,
                    sourceRecord: "QuestionnaireResponse|\(extracted.nativeRecordID)"
                )
                self.content = .success(Content(
                    extracted: extracted,
                    request: exporter.context.request(for: key, recordParts: try Self.recordParts(of: record))
                ))
            } catch {
                self.content = .failure(ObservationExtractionError(conversionFailure: error))
            }
        }

        /// The record parts of a request: the questionnaire and the response as sorted-key JSON.
        ///
        /// The pair is everything a graph states from the record, so another response under a reserved identifier, such
        /// as an amendment, or another revision of the instrument mints a new event instead of restating the reserved one.
        static func recordParts(of record: Record) throws -> [String] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return [
                "questionnaire", String(decoding: try encoder.encode(record.questionnaire), as: UTF8.self),
                "response", String(decoding: try encoder.encode(record.response), as: UTF8.self)
            ]
        }
    }

    /// The planned record's graph under its reservation, or why it has none. A refusal keeps its reservation held: it
    /// is released with the receipt, never mid-call.
    private func deliver(_ plan: Plan, reserved: [ExchangeEventRequest: ExchangeEventReservation]) -> Export.Outcome {
        let content: Plan.Content
        switch plan.content {
        case .failure(let refusal):
            return .refused(refusal)
        case .success(let planned):
            content = planned
        }
        guard let reservation = reserved[content.request] else {
            // An earlier record of this call has the same response identifier, other content, and that key's event.
            return .refused(.conflictingDuplicate)
        }
        do {
            let context = QuestionnaireExtractionContext(
                patient: producer.subject.bundledPatient,
                eventIdentifier: try ExchangeEventIdentifier(
                    system: producer.identityScope.systems.event,
                    producerInstance: reservation.producerInstance,
                    sequence: reservation.sequence
                ),
                identityScope: producer.identityScope,
                repositoryScope: repositoryScope,
                conversionInstant: reservation.instant,
                studies: reservation.facts.studies
            )
            return .graph(try content.extracted.graph(context: context))
        } catch {
            return .refused(ObservationExtractionError(conversionFailure: error))
        }
    }
}


extension ObservationExtractionError {
    /// Narrows any projection failure to this published domain, so nothing unmodelled is relabelled as an extraction
    /// or identity failure.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as ObservationExtractionError:
            self = error
        case let error as ExchangeIdentityError:
            self = .exchangeIdentity(error)
        case let error as OpaqueIdentityError:
            self = .opaqueIdentity(error)
        case let error as ExchangeGraphError:
            self = .exchangeGraph(error)
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
