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
    static func validateStudyContext(entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        var nodes: [String: StudyNode] = [:]
        for (index, entry) in entries.enumerated() {
            guard let role = studyContextRole(of: entry) else {
                continue
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  let resource = entry.resource,
                  resource.resourceType == role.resourceType else {
                throw .ruleViolation(.mobileSupportStudyContext)
            }
            nodes[fullURL] = StudyNode(role: role, object: try jsonObject(at: index, document: document))
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
        let subject = try outputSubject(in: entries, document: document)
        var enrolled: Set<String> = []
        for researchSubject in nodes.values where researchSubject.role == .researchSubject {
            guard let studyURL = (researchSubject.object["study"] as? [String: Any])?["reference"] as? String,
                  studies[studyURL] != nil,
                  let individual = researchSubject.object["individual"] as? [String: Any],
                  let subject,
                  try sameCanonicalJSON(individual, subject),
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
    private static func outputSubject(
        in entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) -> [String: Any]? { // swiftlint:disable:this discouraged_optional_collection
        for (index, entry) in entries.enumerated() {
            guard let resource = entry.resource,
                  ExchangeContract.activeOutputResourceTypes.contains(resource.resourceType) else {
                continue
            }
            return try jsonObject(at: index, document: document)["subject"] as? [String: Any]
        }
        return nil
    }

    private static func jsonObject(at index: Int, document: ValidationDocument) throws(ExchangeGraphError) -> [String: Any] {
        do {
            return try document.resourceObject(at: index) as? [String: Any] ?? [:]
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
    }

    /// Whether `lhs` and `rhs` serialize to the same sorted-keys JSON. Strings, objects with ASCII keys, arrays and nulls
    /// are compared in place; a number or a non-ASCII key falls back to comparing the serializations.
    private static func sameCanonicalJSON(_ lhs: [String: Any], _ rhs: [String: Any]) throws(ExchangeGraphError) -> Bool {
        if let same = equalInPlace(lhs, rhs) {
            return same
        }
        return try canonicalJSON(lhs) == canonicalJSON(rhs)
    }

    /// Whether two JSON values serialize alike, or `nil` for a pair this does not decide: strings compare by their
    /// UTF-8 bytes, as their serializations do, and object keys only when all are ASCII, whose equality is exact.
    private static func equalInPlace(_ lhs: Any, _ rhs: Any) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch (lhs, rhs) {
        case let (lhs as String, rhs as String):
            lhs.utf8.elementsEqual(rhs.utf8)
        case let (lhs as [String: Any], rhs as [String: Any]):
            equalObjectsInPlace(lhs, rhs)
        case let (lhs as [Any], rhs as [Any]):
            lhs.count == rhs.count ? equalAllInPlace(zip(lhs, rhs)) : false
        case (is NSNull, is NSNull):
            true
        default:
            nil
        }
    }

    // swiftlint:disable:next discouraged_optional_boolean
    private static func equalObjectsInPlace(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool? {
        let isASCII = { (key: String) in key.utf8.allSatisfy { $0 < 0x80 } }
        guard lhs.keys.allSatisfy(isASCII), rhs.keys.allSatisfy(isASCII) else {
            return nil
        }
        guard lhs.count == rhs.count else {
            return false
        }
        var pairs: [(Any, Any)] = []
        for (key, value) in lhs {
            guard let other = rhs[key] else {
                return false
            }
            pairs.append((value, other))
        }
        return equalAllInPlace(pairs)
    }

    /// `false` or `nil` for the first pair that is not equal in place, `true` when every pair is.
    private static func equalAllInPlace(_ pairs: some Sequence<(Any, Any)>) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        for (lhs, rhs) in pairs {
            let same = equalInPlace(lhs, rhs)
            if same != true {
                return same
            }
        }
        return true
    }

    private static func canonicalJSON(_ object: [String: Any]) throws(ExchangeGraphError) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
    }
}
