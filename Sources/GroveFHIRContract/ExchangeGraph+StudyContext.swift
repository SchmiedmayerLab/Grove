//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension ContextSnapshotRole {
    /// The role of a context node of `resourceType`, or `nil` for any other resource.
    init?(resourceType: String) {
        switch resourceType {
        case ResourceType.patient.rawValue: self = .patient
        case ResourceType.researchStudy.rawValue: self = .researchStudy
        case ResourceType.researchSubject.rawValue: self = .researchSubject
        case ResourceType.planDefinition.rawValue: self = .planDefinition
        case ResourceType.questionnaireResponse.rawValue: self = .questionnaireResponse
        default: return nil
        }
    }
}


extension ExchangeGraph {
    /// A bundled study context is complete: every ResearchStudy names its exact-revision PlanDefinition, every
    /// PlanDefinition is the protocol of a study, and every study has a ResearchSubject linking the Bundle's subject to it.
    ///
    /// Study nodes are snapshots, so a Bundle whose records span a study revision carries one node per revision. So are
    /// Patients: one participant's records may name their subject through several snapshots, or one of them logically,
    /// so a ResearchSubject repeats what the outputs state, not the reference they state it by.
    static func validateStudyContext(entries: [BundleEntry]) throws(ExchangeGraphError) {
        var plans: [String: PlanDefinition] = [:]
        var studies: [String: ResearchStudy] = [:]
        var researchSubjects: [ResearchSubject] = []
        for entry in entries {
            let fullURL = entry.fullUrl?.value?.url.absoluteString ?? ""
            switch entry.resource {
            case .planDefinition(let plan): plans[fullURL] = plan
            case .researchStudy(let study): studies[fullURL] = study
            case .researchSubject(let researchSubject): researchSubjects.append(researchSubject)
            default: break
            }
        }
        var protocols: Set<String> = []
        for study in studies.values {
            guard let references = study.protocol, references.count == 1,
                  let planURL = references[0].reference?.value?.string,
                  let plan = plans[planURL],
                  plan.url?.value?.url.absoluteString.isEmpty == false,
                  plan.version?.value?.string.isEmpty == false else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
            protocols.insert(planURL)
        }
        let patients = Self.patients(in: entries)
        let subjects = subjectStatements(in: entries)
        var enrolled: Set<String> = []
        for researchSubject in researchSubjects {
            guard let studyURL = researchSubject.study.reference?.value?.string,
                  studies[studyURL] != nil,
                  subjectStatement(researchSubject.individual, patients: patients).map(subjects.contains) == true else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
            enrolled.insert(studyURL)
        }
        guard protocols.count == plans.count, enrolled.count == studies.count else {
            throw .ruleViolation(.mobileSupportStudyContext)
        }
    }

    /// What an active output states as its subject.
    static func outputSubject(of resource: ResourceProxy) -> Reference? {
        switch resource {
        case .observation(let observation): observation.subject
        case .documentReference(let document): document.subject
        case .specimen(let specimen): specimen.subject
        case .medicationAdministration(let administration): administration.subject
        case .medicationStatement(let statement): statement.subject
        case .visionPrescription(let prescription): prescription.patient
        default: nil
        }
    }
}
