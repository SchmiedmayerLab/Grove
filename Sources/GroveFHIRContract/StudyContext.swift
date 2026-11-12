//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
package import ModelsR4


/// The bundled study context of one record: content-keyed entries, and the references outputs make to them.
package struct StudyContext: Sendable {
    /// The Patient entry when the subject is bundled, first among the context entries.
    package let patient: BundleEntry?
    /// ResearchStudy, PlanDefinition and ResearchSubject entries, in that order per enrollment.
    package let entries: [BundleEntry]
    /// What every output's `subject` states: the Patient entry or the identifier-only pseudonym.
    package let subjectReference: Reference
    /// One resolving literal reference per ResearchStudy entry, for `workflow-researchStudy`.
    package let studyReferences: [Reference]

    package var allEntries: [BundleEntry] {
        [patient].compactMap { $0 } + entries
    }
}


extension StudyContext {
    private static let patientType = FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.patient.rawValue))
    private static let researchStudyType = FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.researchStudy.rawValue))

    /// The study context the catalog recommends for the subject and known enrollments of one record, each node keyed by
    /// its content.
    package init(
        subject: Subject,
        studies: [StudyEnrollment],
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) {
        var patientEntry: BundleEntry?
        let subjectReference: Reference
        switch subject {
        case .logical(let identifier):
            subjectReference = identifier.reference(to: .patient)
        case .bundled:
            let entry = try Self.patientEntry(subject.bundledPatient, subject: subject.identifier, identityScope: identityScope)
            patientEntry = entry
            subjectReference = Reference(reference: entry.fullUrl?.value?.url.absoluteString.asFHIRStringPrimitive(), type: Self.patientType)
        }
        let enrolled = try StudyContext(
            studies: studies,
            subject: subject.identifier,
            subjectReference: subjectReference,
            identityScope: identityScope
        )
        self.init(patient: patientEntry, entries: enrolled.entries, subjectReference: subjectReference, studyReferences: enrolled.studyReferences)
    }

    /// The study context of a record that bundles and references its subject itself, as Questionnaire's bundles its own
    /// Patient: no Patient entry, and every ResearchSubject names `subjectReference`.
    package init(
        studies: [StudyEnrollment],
        subject: BusinessIdentifier,
        subjectReference: Reference,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) {
        var entries: [BundleEntry] = []
        var studyReferences: [Reference] = []
        var stated: Set<String> = []
        for enrollment in studies {
            let study = try Self.studyEntries(for: enrollment, subject: subject, subjectReference: subjectReference, identityScope: identityScope)
            // Two enrollments under one protocol revision share its one PlanDefinition snapshot.
            entries += study.entries.filter { stated.insert($0.fullUrl?.value?.url.absoluteString ?? "").inserted }
            studyReferences.append(study.reference)
        }
        self.init(patient: nil, entries: entries, subjectReference: subjectReference, studyReferences: studyReferences)
    }

    /// The Patient entry of `patient`, keyed by its content, which it repeats as a `context-snapshot` identifier.
    package static func patientEntry(
        _ patient: Patient,
        subject: BusinessIdentifier,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) -> BundleEntry {
        let key = try identityScope.contentSnapshot(of: patient, subject: subject, role: .context(.patient))
        var keyed = patient
        keyed.identifier = (patient.identifier ?? []) + [key.fhirIdentifier]
        return try BundleEntry(identifier: key, resource: ResourceProxy(with: keyed))
    }

    /// One enrollment's ResearchStudy, PlanDefinition and ResearchSubject entries and the study reference outputs carry.
    ///
    /// Each node is keyed after the nodes it references: the plan, the study that names it, the subject that names the
    /// study. Each repeats its key as a `context-snapshot` identifier beside any business identifier it has.
    private static func studyEntries(
        for enrollment: StudyEnrollment,
        subject: BusinessIdentifier,
        subjectReference: Reference,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) -> (entries: [BundleEntry], reference: Reference) {
        var plan = PlanDefinition(
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: enrollment.protocolURL.value?.url.absoluteString ?? "")),
            version: enrollment.protocolVersion.asFHIRStringPrimitive()
        )
        let planKey = try identityScope.contentSnapshot(of: plan, subject: subject, role: .context(.planDefinition))
        plan.identifier = [planKey.fhirIdentifier]
        let planURL = try planKey.fullURLString

        var study = ResearchStudy(
            identifier: [enrollment.study.fhirIdentifier],
            protocol: [Reference(reference: planURL.asFHIRStringPrimitive())],
            status: FHIRPrimitive(.active)
        )
        let studyKey = try identityScope.contentSnapshot(of: study, subject: subject, role: .context(.researchStudy))
        study.identifier = [enrollment.study.fhirIdentifier, studyKey.fhirIdentifier]
        let studyURL = try studyKey.fullURLString

        var researchSubject = ResearchSubject(
            identifier: [enrollment.enrollment.fhirIdentifier],
            individual: subjectReference,
            status: FHIRPrimitive(.onStudy),
            study: Reference(reference: studyURL.asFHIRStringPrimitive())
        )
        let subjectKey = try identityScope.contentSnapshot(of: researchSubject, subject: subject, role: .context(.researchSubject))
        researchSubject.identifier = [enrollment.enrollment.fhirIdentifier, subjectKey.fhirIdentifier]

        let entries = [
            BundleEntry(identifier: studyKey, fullURL: studyURL, resource: ResourceProxy(with: study)),
            BundleEntry(identifier: planKey, fullURL: planURL, resource: ResourceProxy(with: plan)),
            try BundleEntry(identifier: subjectKey, resource: ResourceProxy(with: researchSubject))
        ]
        return (entries, Reference(reference: studyURL.asFHIRStringPrimitive(), type: Self.researchStudyType))
    }
}
