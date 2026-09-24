//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


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


extension ExchangeEventContext {
    /// Builds the entry-node keyed study context the catalog recommends for a known enrollment.
    package func studyContext() throws(ExchangeIdentityError) -> StudyContext {
        var patientEntry: BundleEntry?
        let subjectReference: Reference
        switch subject {
        case .logical(let identifier):
            subjectReference = identifier.reference(to: .patient)
        case .bundled(let identifier, var patient):
            if patient.identifier?.contains(identifier.fhirIdentifier) != true {
                patient.identifier = (patient.identifier ?? []) + [identifier.fhirIdentifier]
            }
            let key = try nodeKey(.patient, ordinal: 0)
            let entry = try BundleEntry(identifier: key.identifier, resource: ResourceProxy(with: patient))
            patientEntry = entry
            subjectReference = Reference(
                reference: try key.identifier.identifier.fullURLString.asFHIRStringPrimitive(),
                type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.patient.rawValue))
            )
        }
        var entries: [BundleEntry] = []
        var studyReferences: [Reference] = []
        for (ordinal, enrollment) in studies.enumerated() {
            let study = try studyEntries(for: enrollment, ordinal: UInt64(ordinal), subjectReference: subjectReference)
            entries.append(contentsOf: study.entries)
            studyReferences.append(study.reference)
        }
        return StudyContext(
            patient: patientEntry,
            entries: entries,
            subjectReference: subjectReference,
            studyReferences: studyReferences
        )
    }

    /// One enrollment's ResearchStudy, PlanDefinition and ResearchSubject entries, and the study reference outputs carry.
    private func studyEntries(
        for enrollment: StudyEnrollment,
        ordinal: UInt64,
        subjectReference: Reference
    ) throws(ExchangeIdentityError) -> (entries: [BundleEntry], reference: Reference) {
        let studyKey = try nodeKey(.researchStudy, ordinal: ordinal)
        let planKey = try nodeKey(.planDefinition, ordinal: ordinal)
        let subjectKey = try nodeKey(.researchSubject, ordinal: ordinal)
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

    /// What every output's `subject` states, derived the same way the bundled study context is.
    package func subjectReference() throws(ExchangeIdentityError) -> Reference {
        try studyContext().subjectReference
    }

    /// One resolving literal reference per bundled ResearchStudy entry.
    package func studyReferences() throws(ExchangeIdentityError) -> [Reference] {
        try studyContext().studyReferences
    }

    /// The application that mediated the measurement: the converter itself, a distinct application
    /// snapshot, or none.
    package func gatewayURL(converterURL: String) throws(OpaqueIdentityError) -> String? {
        switch converterRole {
        case .assembler:
            return nil
        case .gateway:
            return converterURL
        case .gatewayApplication(let application):
            let snapshot = try identityScope.deviceSnapshot(
                event: event,
                role: .application,
                sourceDeviceToken: application.sourceDeviceToken
            )
            return try? snapshot.fullURLString
        }
    }

    private func nodeKey(_ role: StudyContextEntryNodeRole, ordinal: UInt64) throws(ExchangeIdentityError) -> EntryNodeKey {
        try EntryNodeKey(system: entryNodeIdentifierSystem, event: event, nodeRole: role.rawValue, ordinal: ordinal)
    }
}
