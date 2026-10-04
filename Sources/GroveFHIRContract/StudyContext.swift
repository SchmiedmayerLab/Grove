//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
package import ModelsR4


/// The bundled study context of one event: entries keyed by entry-node role, and the references
/// outputs make to them.
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
    /// The entry-node keyed study context the catalog recommends for the subject and known enrollments of one event,
    /// each node keyed in `identityScope`'s entry-node system.
    package init(
        subject: Subject,
        studies: [StudyEnrollment],
        event: ExchangeEventIdentifier,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) {
        var patientEntry: BundleEntry?
        let subjectReference: Reference
        switch subject {
        case .logical(let identifier):
            subjectReference = identifier.reference(to: .patient)
        case .bundled:
            let key = try EntryNodeKey(
                system: identityScope.systems.entryNode,
                event: event,
                nodeRole: StudyContextEntryNodeRole.patient.rawValue,
                ordinal: 0
            )
            patientEntry = try BundleEntry(identifier: key.identifier, resource: ResourceProxy(with: subject.bundledPatient))
            subjectReference = Reference(
                reference: try key.identifier.identifier.fullURLString.asFHIRStringPrimitive(),
                type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.patient.rawValue))
            )
        }
        let enrolled = try StudyContext(studies: studies, subjectReference: subjectReference, event: event, identityScope: identityScope)
        self.init(patient: patientEntry, entries: enrolled.entries, subjectReference: subjectReference, studyReferences: enrolled.studyReferences)
    }

    /// The study context of a graph that bundles and references its subject itself, as Questionnaire's bundles its own
    /// Patient: no Patient entry, and every ResearchSubject names `subjectReference`.
    package init(
        studies: [StudyEnrollment],
        subjectReference: Reference,
        event: ExchangeEventIdentifier,
        identityScope: OpaqueIdentityScope
    ) throws(ExchangeIdentityError) {
        var entries: [BundleEntry] = []
        var studyReferences: [Reference] = []
        for (ordinal, enrollment) in studies.enumerated() {
            let study = try Self.studyEntries(for: enrollment, subjectReference: subjectReference) { role throws(ExchangeIdentityError) in
                try EntryNodeKey(system: identityScope.systems.entryNode, event: event, nodeRole: role.rawValue, ordinal: UInt64(ordinal))
            }
            entries.append(contentsOf: study.entries)
            studyReferences.append(study.reference)
        }
        self.init(patient: nil, entries: entries, subjectReference: subjectReference, studyReferences: studyReferences)
    }

    /// One enrollment's ResearchStudy, PlanDefinition and ResearchSubject entries, each under the key `nodeKey` mints
    /// for its role, and the study reference outputs carry.
    private static func studyEntries(
        for enrollment: StudyEnrollment,
        subjectReference: Reference,
        nodeKey: (StudyContextEntryNodeRole) throws(ExchangeIdentityError) -> EntryNodeKey
    ) throws(ExchangeIdentityError) -> (entries: [BundleEntry], reference: Reference) {
        let studyKey = try nodeKey(.researchStudy)
        let planKey = try nodeKey(.planDefinition)
        let subjectKey = try nodeKey(.researchSubject)
        let studyURL = try studyKey.identifier.identifier.fullURLString
        let planURL = try planKey.identifier.identifier.fullURLString
        let study = ResearchStudy(
            identifier: [enrollment.study.fhirIdentifier],
            protocol: [Reference(reference: planURL.asFHIRStringPrimitive())],
            status: FHIRPrimitive(.active)
        )
        let plan = PlanDefinition(
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: enrollment.protocolURL.value?.url.absoluteString ?? "")),
            version: enrollment.protocolVersion.asFHIRStringPrimitive()
        )
        let researchSubject = ResearchSubject(
            identifier: [enrollment.enrollment.fhirIdentifier],
            individual: subjectReference,
            status: FHIRPrimitive(.onStudy),
            study: Reference(reference: studyURL.asFHIRStringPrimitive())
        )
        let entries = [
            try BundleEntry(identifier: studyKey.identifier, resource: ResourceProxy(with: study)),
            try BundleEntry(identifier: planKey.identifier, resource: ResourceProxy(with: plan)),
            try BundleEntry(identifier: subjectKey.identifier, resource: ResourceProxy(with: researchSubject))
        ]
        let reference = Reference(
            reference: studyURL.asFHIRStringPrimitive(),
            type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.researchStudy.rawValue))
        )
        return (entries, reference)
    }
}
