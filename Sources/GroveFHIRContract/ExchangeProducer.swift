//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Who is exporting: one deployment, one participant, one application installation.
///
/// Immutable; rebuild it when any input changes. The inputs every record shares are checked once
/// here, so a deployment fault is reported where the producer is configured rather than inside a
/// conversion.
public struct ExchangeProducer: Sendable {
    /// A configuration the producer refuses, as every record built under it would be refused.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The subject's pseudonym is numbered in one of the deployment's own graph identity systems.
        case reservedSubjectIdentifierSystem(IdentifierSystem)
        /// A study or enrollment identifier is numbered in one of the deployment's own graph identity systems.
        case reservedStudyIdentifierSystem(IdentifierSystem)
        /// Two enrollments name the same study.
        case duplicateStudy(BusinessIdentifier)
        /// Two enrollments carry the same enrollment identifier.
        case duplicateEnrollment(BusinessIdentifier)
        /// The bundled Patient carries an identifier without a Grove role besides the pseudonym, such as a medical record
        /// number, so it would name no one pseudonym.
        case bundledPatientIdentifiers

        /// The registered diagnostic: every configuration fault is a deployment defect.
        public var diagnostic: ProducerDiagnostic {
            ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: "ExchangeProducer")
        }
    }

    /// The deployment's scope that mints every opaque identity.
    package let identityScope: OpaqueIdentityScope
    /// The participant every record is about.
    package let subject: Subject
    /// What every record states about the application, its host and the participant's studies.
    public let facts: ConversionFacts

    /// Creates the producer of one installation.
    ///
    /// - Parameters:
    ///   - identityScope: The deployment's scope that mints every opaque identity.
    ///   - subject: The participant every record is about.
    ///   - application: The converting application, as its Device snapshot states it.
    ///   - host: The host the application runs on; captured now, as a later snapshot may differ.
    ///   - studies: The participant's known enrollments, each study once.
    public init(
        identityScope: OpaqueIdentityScope,
        subject: Subject,
        application: ApplicationDevice,
        host: HostDevice = .current(),
        studies: [StudyEnrollment] = []
    ) throws(ConfigurationError) {
        let reserved = identityScope.systems.all
        guard !reserved.contains(subject.identifier.system) else {
            throw .reservedSubjectIdentifierSystem(subject.identifier.system)
        }
        if case .bundled = subject, ExchangeGraph.patientPseudonym(subject.bundledPatient) != subject.identifier {
            throw .bundledPatientIdentifiers
        }
        var seenStudies: Set<BusinessIdentifier> = []
        var seenEnrollments: Set<BusinessIdentifier> = []
        for enrollment in studies {
            for identifier in [enrollment.study, enrollment.enrollment] where reserved.contains(identifier.system) {
                throw .reservedStudyIdentifierSystem(identifier.system)
            }
            guard seenStudies.insert(enrollment.study).inserted else {
                throw .duplicateStudy(enrollment.study)
            }
            guard seenEnrollments.insert(enrollment.enrollment).inserted else {
                throw .duplicateEnrollment(enrollment.enrollment)
            }
        }
        self.identityScope = identityScope
        self.subject = subject
        self.facts = ConversionFacts(application: application, host: host, studies: studies)
    }
}
