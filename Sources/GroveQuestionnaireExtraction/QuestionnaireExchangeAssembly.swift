//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation
package import GroveFHIRContract
package import ModelsR4


/// Everything one projection needs beyond the pair itself: the event, its instant, and what the graph states about
/// the participant.
///
/// ``QuestionnaireFHIRExporter`` builds one per event from its reservation; tests build one directly to project the
/// guide's worked example under its published event.
package struct QuestionnaireExtractionContext: Sendable {
    /// The Patient the exchange Bundle carries; every subject and performer resolves to it.
    package let patient: ModelsR4.Patient
    package let eventIdentifier: ExchangeEventIdentifier
    package let identityScope: OpaqueIdentityScope
    package let repositoryScope: BusinessIdentifier
    /// The instant of this projection event, which `Bundle.timestamp` and the Provenance state at millisecond precision.
    package let conversionInstant: Date
    /// The participant's enrollments, stated as the graph's study context.
    package let studies: [StudyEnrollment]

    package init(
        patient: ModelsR4.Patient,
        eventIdentifier: ExchangeEventIdentifier,
        identityScope: OpaqueIdentityScope,
        repositoryScope: BusinessIdentifier,
        conversionInstant: Date,
        studies: [StudyEnrollment] = []
    ) {
        self.patient = patient
        self.eventIdentifier = eventIdentifier
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.conversionInstant = conversionInstant
        self.studies = studies
    }
}


/// Projects one Questionnaire/Response pair into a complete Grove exchange graph.
///
/// The Bundle carries the Patient, the study context when the participant is enrolled, the response, the writer's
/// host and application snapshots, one Observation per extracted measurement, and the conversion Provenance, in the
/// order the questionnaire guide's worked example documents. Every internal reference is the literal deterministic URN
/// of another entry, so the graph resolves without any repository. The Device bodies and the Provenance come from the
/// builders the shared assembler uses; the entry list and the response-derived parts are the projection's own.
package enum QuestionnaireExchangeProjection {
    static let adapterID = "questionnaire"
    /// The revision of the graphs this projection builds. Bump it whenever the bytes it emits can change for equal
    /// inputs: it enters the exporter's context fingerprint beside the shared builders' revision.
    static let outputRevision: UInt = 1

    /// Extracts every answered marked measurement and returns the exchange bundle carrying them.
    ///
    /// A marked item or panel the participant left unanswered extracts nothing unless the instrument
    /// declares it `required`; a panel answered only in part refuses.
    package static func exchangeGraph(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        context: QuestionnaireExtractionContext
    ) throws -> ExchangeGraph {
        try ExtractedResponse(
            questionnaire: questionnaire,
            response: response,
            identityScope: context.identityScope,
            repositoryScope: context.repositoryScope
        ).graph(context: context)
    }
}


// MARK: Extracted Response

/// One response's measurements and the event-independent facts its graph states, validated before any event exists,
/// so a response that cannot be projected never reserves one.
struct ExtractedResponse {
    let response: ModelsR4.QuestionnaireResponse
    let measurements: [ExtractedMeasurement]
    let writer: QuestionnaireWriterContext
    let authored: DateTime
    /// The response's business identifier value, which names the source record and keys its event.
    let nativeRecordID: String
    let sourceRecord: SourceRecordIdentity

    init(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        identityScope: OpaqueIdentityScope,
        repositoryScope: BusinessIdentifier
    ) throws {
        let measurements = try QuestionnaireObservationExtractor(questionnaire: questionnaire, response: response).extract()
        // An exchange event must carry at least one source output; an unmarked instrument, or a
        // response answering none of its marked items, refuses here, before any identity is minted.
        guard !measurements.isEmpty else {
            throw ObservationExtractionError.noExtractableMeasurements
        }
        guard let writer = try response.writerContext() else {
            throw ObservationExtractionError.writerContextMissing
        }
        guard let nativeRecordID = response.identifier?.value?.value?.string else {
            throw ObservationExtractionError.responseIdentifierMissing
        }
        guard QuestionnaireCanonicalIdentity(response.questionnaire) != nil else {
            throw ObservationExtractionError.versionedQuestionnaireCanonicalMissing
        }
        guard let authored = response.authored?.value else {
            throw ObservationExtractionError.responseAuthoredMissing
        }
        try Self.validateActors(of: response)
        self.response = response
        self.measurements = measurements
        self.writer = writer
        self.authored = authored
        self.nativeRecordID = nativeRecordID
        // The source type names the record kind, as every adapter's does; which instrument was
        // answered stays in the response the Observations derive from.
        self.sourceRecord = try identityScope.sourceRecord(
            adapterID: QuestionnaireExchangeProjection.adapterID,
            sourceType: "QuestionnaireResponse",
            repositoryScope: repositoryScope,
            nativeRecordID: nativeRecordID
        )
    }
}


extension ExtractedResponse {
    /// Refuses a response whose author or source is anyone but its subject.
    ///
    /// Author and source are independent facts the guide forbids inferring from one another, so a
    /// caregiver-authored response refuses here instead of being silently re-attributed.
    static func validateActors(of response: ModelsR4.QuestionnaireResponse) throws {
        guard let subject = response.subject else {
            throw ObservationExtractionError.subjectMissing
        }
        if let author = response.author, !denotesSameActor(author, as: subject) {
            throw ObservationExtractionError.authorIsNotTheSubject
        }
        if let source = response.source, !denotesSameActor(source, as: subject) {
            throw ObservationExtractionError.sourceIsNotTheSubject
        }
    }

    /// Whether two references name the same actor, ignoring display text that does not.
    static func denotesSameActor(_ reference: Reference, as subject: Reference) -> Bool {
        guard reference.reference != nil || reference.identifier != nil else {
            return false
        }
        return reference.reference?.value?.string == subject.reference?.value?.string
            && reference.identifier == subject.identifier
            && reference.type?.value?.url == subject.type?.value?.url
    }

    /// The validated graph of this response under the event `context` names.
    func graph(context: QuestionnaireExtractionContext) throws -> ExchangeGraph {
        let frame = try GraphFrame(extracted: self, context: context)
        var entries = try frame.supportEntries()
        var observationURLs: [String] = []
        for measurement in measurements {
            let (entry, url) = try frame.observationEntry(for: measurement)
            entries.append(entry)
            observationURLs.append(url)
        }
        entries.append(try frame.provenanceEntry(targets: observationURLs))
        return try frame.graph(entries: entries)
    }
}
