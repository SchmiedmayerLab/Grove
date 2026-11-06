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


/// Everything one projection needs beyond the pair itself: the conversion instant, and what the record states about the
/// participant.
///
/// ``QuestionnaireFHIRExporter`` builds one per record; tests build one directly to project the guide's worked example.
package struct QuestionnaireExtractionContext: Sendable {
    /// The Patient the record carries; every subject and performer resolves to it.
    package let patient: ModelsR4.Patient
    /// The participant's pseudonym, which every content key is scoped to.
    package let subject: BusinessIdentifier
    package let identityScope: OpaqueIdentityScope
    package let repositoryScope: BusinessIdentifier
    /// The instant of this projection, which the Provenance states at millisecond precision.
    package let conversionInstant: Date
    /// The participant's enrollments, stated as the record's study context.
    package let studies: [StudyEnrollment]

    package init(
        patient: ModelsR4.Patient,
        subject: BusinessIdentifier,
        identityScope: OpaqueIdentityScope,
        repositoryScope: BusinessIdentifier,
        conversionInstant: Date,
        studies: [StudyEnrollment] = []
    ) {
        self.patient = patient
        self.subject = subject
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.conversionInstant = conversionInstant
        self.studies = studies
    }
}


/// Projects one Questionnaire/Response pair into a complete Grove exchange record.
///
/// The record carries the Patient, the study context when the participant is enrolled, the response, the writer's
/// host and application snapshots, one Observation per extracted measurement, and the conversion Provenance, in the
/// order the questionnaire guide's worked example documents. Every internal reference is the literal deterministic URN
/// of another entry, so the record resolves without any repository. The Device bodies, the Provenance and the record
/// version come from the builders the shared assembler uses; the entry list and the response-derived parts are the
/// projection's own.
package enum QuestionnaireExchangeProjection {
    static let adapterID = "questionnaire"

    /// What a retraction states about its converting application.
    static let adapter = ExchangeAdapterContract(
        adapterID: adapterID,
        provenanceProfile: Profile.groveMobileConversionProvenance,
        applicationDeviceProfile: Profile.groveApplicationDevice
    ) { $0.appleBundleIdentifier }

    /// Extracts every answered marked measurement and returns the exchange record carrying them.
    ///
    /// A marked item or panel the participant left unanswered extracts nothing unless the instrument
    /// declares it `required`; a panel answered only in part refuses.
    package static func exchangeRecord(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        context: QuestionnaireExtractionContext
    ) throws -> ExchangeRecord {
        try ExtractedResponse(
            questionnaire: questionnaire,
            response: response,
            identityScope: context.identityScope,
            repositoryScope: context.repositoryScope
        ).record(context: context)
    }
}


// MARK: Extracted Response

/// One response's measurements and the facts its record states, validated before any record is built.
struct ExtractedResponse {
    let response: ModelsR4.QuestionnaireResponse
    let measurements: [ExtractedMeasurement]
    let writer: QuestionnaireWriterContext
    let authored: DateTime
    /// Named by the response's business identifier value.
    let sourceRecord: SourceRecordIdentity

    init(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        identityScope: OpaqueIdentityScope,
        repositoryScope: BusinessIdentifier
    ) throws {
        let measurements = try QuestionnaireObservationExtractor(questionnaire: questionnaire, response: response).extract()
        // A record must carry at least one source output; an unmarked instrument, or a response answering none of its
        // marked items, refuses here, before any identity is minted.
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

    /// The validated record of this response under `context`.
    func record(context: QuestionnaireExtractionContext) throws -> ExchangeRecord {
        let frame = try GraphFrame(extracted: self, context: context)
        var entries = frame.supportEntries()
        var observationURLs: [String] = []
        for measurement in measurements {
            let (entry, url) = try frame.observationEntry(for: measurement)
            entries.append(entry)
            observationURLs.append(url)
        }
        return try ExchangeGraphAssembler.conversionRecord(
            provenance: try frame.provenance(targets: observationURLs),
            sourceRecord: sourceRecord.identifier,
            entries: entries,
            subject: context.subject,
            identityScope: context.identityScope
        )
    }
}
