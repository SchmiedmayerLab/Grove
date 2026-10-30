//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension StudyContextEntryNodeRole {
    var resourceType: String {
        switch self {
        case .patient: ResourceType.patient.rawValue
        case .researchStudy: ResourceType.researchStudy.rawValue
        case .researchSubject: ResourceType.researchSubject.rawValue
        case .planDefinition: ResourceType.planDefinition.rawValue
        }
    }
}


extension ExchangeGraph {
    private struct StudyNode {
        let role: StudyContextEntryNodeRole
        let object: [String: Any]
    }

    /// A bundled study context is complete: every ResearchStudy names its exact-revision PlanDefinition,
    /// exactly one ResearchSubject links the graph's subject to it, and each entry sits under its own role.
    static func validateStudyContext(entries: [BundleEntry]) throws(ExchangeGraphError) {
        var nodes: [String: StudyNode] = [:]
        for entry in entries {
            guard let role = studyContextRole(of: entry) else {
                continue
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  let resource = entry.resource,
                  resource.resourceType == role.resourceType else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
            nodes[fullURL] = StudyNode(role: role, object: try jsonObject(of: resource))
        }
        let studies = nodes.filter { $0.value.role == .researchStudy }
        let plans = nodes.filter { $0.value.role == .planDefinition }
        var protocols: Set<String> = []
        for study in studies.values {
            guard let references = study.object["protocol"] as? [[String: Any]], references.count == 1,
                  let planURL = references[0]["reference"] as? String,
                  let plan = plans[planURL],
                  (plan.object["url"] as? String)?.isEmpty == false,
                  (plan.object["version"] as? String)?.isEmpty == false,
                  protocols.insert(planURL).inserted else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
        }
        let subject = try outputSubject(in: entries)
        var enrolled: Set<String> = []
        for researchSubject in nodes.values where researchSubject.role == .researchSubject {
            guard let studyURL = (researchSubject.object["study"] as? [String: Any])?["reference"] as? String,
                  studies[studyURL] != nil,
                  let individual = researchSubject.object["individual"] as? [String: Any],
                  try canonicalJSON(individual) == subject,
                  enrolled.insert(studyURL).inserted else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
        }
        guard protocols.count == plans.count, enrolled.count == studies.count else {
            throw .ruleViolation(.mobileSupportStudyContext)
        }
    }

    private static func studyContextRole(of entry: BundleEntry) -> StudyContextEntryNodeRole? {
        let key = entry.extension?.first { $0.url == Canonicals.entryNodeKey }
        guard case .identifier(let identifier)? = key?.value,
              let value = identifier.value?.value?.string else {
            return nil
        }
        let parts = value.split(separator: ":", maxSplits: 2)
        guard parts.count == 3, parts[0] == "n0" else {
            return nil
        }
        return StudyContextEntryNodeRole(rawValue: String(parts[1]))
    }

    /// What the first output states as its subject, the reference every ResearchSubject must repeat.
    private static func outputSubject(in entries: [BundleEntry]) throws(ExchangeGraphError) -> Data? {
        for entry in entries {
            guard let resource = entry.resource,
                  ExchangeContract.activeOutputResourceTypes.contains(resource.resourceType) else {
                continue
            }
            guard let subject = try jsonObject(of: resource)["subject"] as? [String: Any] else {
                return nil
            }
            return try canonicalJSON(subject)
        }
        return nil
    }

    private static func jsonObject(of resource: ResourceProxy) throws(ExchangeGraphError) -> [String: Any] {
        do {
            return try JSONSerialization.jsonObject(with: try JSONEncoder().encode(resource)) as? [String: Any] ?? [:]
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
    }

    private static func canonicalJSON(_ object: [String: Any]) throws(ExchangeGraphError) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
    }
}
