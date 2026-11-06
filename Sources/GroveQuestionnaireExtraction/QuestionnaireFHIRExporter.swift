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


/// Turns completed QuestionnaireResponses into exchange records for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share across tasks. A
/// response that cannot be projected is reported as a refusal instead of ending the call.
///
/// Each record is the projection the questionnaire guide's worked example documents: the Patient, the response, the
/// application and host snapshots of the writer the response's writer context names, one Observation per extracted
/// measurement and the conversion Provenance, plus the study context when the producer knows the participant's
/// enrollments. The Patient is the producer's subject: the Patient it bundles, or one stating only the pseudonym. A
/// Questionnaire record states the writer rather than the producer's application and host.
/// ``retract(_:at:receive:)`` takes a withdrawn response back.
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

    /// What one input produced: an exchange record, or the reason it produced none.
    public struct Export: Sendable {
        public enum Outcome: Sendable {
            /// The validated record; stage `ExchangeRecord.json` verbatim, and pack it for upload.
            case record(ExchangeRecord)
            /// The record was refused; nothing was emitted and the export continued. Refusals are deterministic,
            /// so an exact redelivery refuses identically.
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

    let producer: ExchangeProducer
    /// The business identifier naming the store the responses come from; it enters every source identity.
    let repositoryScope: BusinessIdentifier

    /// Creates the exporter of one installation's questionnaire responses.
    ///
    /// - Parameters:
    ///   - producer: The producer whose studies each record states.
    ///   - repositoryScope: The business identifier naming the store the responses come from; it enters every source
    ///     identity.
    public init(producer: ExchangeProducer, repositoryScope: BusinessIdentifier) {
        self.producer = producer
        self.repositoryScope = repositoryScope
    }

    /// Projects records in input order, calling `receive` once per record with its exchange record or its refusal.
    ///
    /// A record that cannot be projected is refused in place. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant`;
    /// - errors of `receive` are rethrown unchanged.
    ///
    /// - Parameters:
    ///   - records: The responses to project, each with the instrument it answers.
    ///   - instant: The conversion instant.
    ///   - receive: Called once per record, in input order.
    nonisolated(nonsending) public func export(
        _ records: some Collection<Record>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil else {
            throw ExchangeIdentityError.invalidInstant
        }
        for record in records {
            let responseIdentifier = record.response.identifier?.value?.value?.string
            try receive(Export(responseIdentifier: responseIdentifier, outcome: outcome(of: record, at: instant)))
        }
    }
}


extension QuestionnaireFHIRExporter {
    /// The extraction of one record.
    func extraction(of record: Record) throws -> ExtractedResponse {
        try ExtractedResponse(
            questionnaire: record.questionnaire,
            response: record.response,
            identityScope: producer.identityScope,
            repositoryScope: repositoryScope
        )
    }

    /// The record's projection, or why it has none.
    private func outcome(of record: Record, at instant: Date) -> Export.Outcome {
        do {
            let context = QuestionnaireExtractionContext(
                patient: producer.subject.bundledPatient,
                subject: producer.subject.identifier,
                identityScope: producer.identityScope,
                repositoryScope: repositoryScope,
                conversionInstant: instant,
                studies: producer.facts.studies
            )
            return .record(try extraction(of: record).record(context: context))
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
        case let error as ExchangeGraphError:
            self = .exchangeGraph(error)
        case let error as RetractionRecord.ValidationError:
            self = switch error {
            case .exchangeIdentity(let error): .exchangeIdentity(error)
            case .exchangeGraph(let error): .exchangeGraph(error)
            // A withdrawal instant no FHIR dateTime can state.
            case .invalidInstant: .exchangeIdentity(.invalidInstant)
            case .emptyTargets, .duplicateTarget, .invalidSourceRecord, .reservedIdentifierSystem, .invalidOccurrencePeriod:
                .unexpectedConversionFailure(String(reflecting: type(of: error)))
            }
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}
