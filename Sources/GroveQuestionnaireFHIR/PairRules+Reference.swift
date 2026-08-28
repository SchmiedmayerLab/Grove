//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

extension PairRules {
    static func validateSubjectType(
        questionnaire: FHIRJSONObject,
        response: FHIRJSONObject,
        issues: inout [ValidationIssue]
    ) {
        guard let subject = response["subject"],
              let admitted = questionnaire["subjectType"] as? [String],
              !admitted.isEmpty else {
            return
        }
        let actual = referenceResourceType(subject, containingResource: response)
        guard let actual, admitted.contains(actual) else {
            issues.append(.init(
                code: .subjectType,
                path: "QuestionnaireResponse.subject",
                message: "QuestionnaireResponse.subject must target one of Questionnaire.subjectType "
                    + "\(admitted.sorted()); found \(String(describing: actual))."
            ))
            return
        }
    }

    /// Resolves a Reference's target type only when its declared type and locally observable
    /// target agree. Identifier-only references therefore require `Reference.type`; literal
    /// references may derive it from a relative/absolute URL or one uniquely contained resource.
    static func referenceResourceType(
        _ value: Any,
        containingResource: FHIRJSONObject
    ) -> String? {
        guard let reference = value as? FHIRJSONObject else {
            return nil
        }
        let declaredType: String?
        if let rawDeclaredType = reference["type"] {
            guard let rawDeclaredType = rawDeclaredType as? String,
                  let normalized = normalizedReferenceType(rawDeclaredType) else {
                return nil
            }
            declaredType = normalized
        } else {
            declaredType = nil
        }

        guard let literal = reference["reference"] as? String, !literal.isEmpty else {
            return declaredType
        }
        let literalType: String?
        if literal.first == "#" {
            let containedID = String(literal.dropFirst())
            let matches = (containingResource["contained"] as? [FHIRJSONObject] ?? []).filter {
                $0["id"] as? String == containedID
            }
            literalType = matches.count == 1 ? matches[0]["resourceType"] as? String : nil
        } else if let pattern = literalReferenceTypePattern {
            let fullRange = NSRange(literal.startIndex..., in: literal)
            if let match = pattern.firstMatch(in: literal, options: [], range: fullRange),
               let typeRange = Swift.Range(match.range(at: 1), in: literal) {
                literalType = String(literal[typeRange])
            } else {
                literalType = nil
            }
        } else {
            literalType = nil
        }

        if let declaredType, let literalType, declaredType != literalType {
            return nil
        }
        return declaredType ?? literalType
    }

    /// R4 `Reference.type` admits either the relative resource type or its exact core
    /// StructureDefinition canonical. A URI from another namespace is not evidence of a
    /// target type merely because its final path segment happens to resemble one.
    static func normalizedReferenceType(_ value: String) -> String? {
        let corePrefix = "http://hl7.org/fhir/StructureDefinition/"
        let candidate: Substring
        if value.hasPrefix(corePrefix) {
            candidate = value.dropFirst(corePrefix.count)
        } else {
            guard !value.contains("/") else {
                return nil
            }
            candidate = value[...]
        }

        let normalized = String(candidate)
        guard normalized.range(
            of: #"^[A-Z][A-Za-z0-9]*$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return normalized
    }

    static func validateProfile(
        in resource: FHIRJSONObject,
        expected: String?,
        code: ValidationIssue.Code,
        path: String,
        issues: inout [ValidationIssue]
    ) {
        let profiles = (resource["meta"] as? FHIRJSONObject)?["profile"] as? [String] ?? []
        guard let expected, profiles == [expected] else {
            issues.append(.init(
                code: code,
                path: path,
                message: "Expected exactly the Grove profile claim."
            ))
            return
        }
    }

    static func isCompleteIdentifier(_ value: Any?) -> Bool {
        guard let identifier = value as? FHIRJSONObject,
              let system = identifier["system"] as? String,
              !system.isEmpty,
              let identifierValue = identifier["value"] as? String,
              !identifierValue.isEmpty else {
            return false
        }
        return Foundation.URL(string: system)?.scheme != nil
    }

    static func collectDefinitionIDs(
        _ definitions: [FHIRJSONObject],
        into identifiers: inout Set<String>
    ) {
        for definition in definitions {
            if let linkID = definition["linkId"] as? String {
                identifiers.insert(linkID)
            }
            collectDefinitionIDs(
                definition["item"] as? [FHIRJSONObject] ?? [],
                into: &identifiers
            )
        }
    }

    static func extensions(
        _ element: FHIRJSONObject,
        url: String
    ) -> [FHIRJSONObject] {
        (element["extension"] as? [FHIRJSONObject] ?? []).filter { $0["url"] as? String == url }
    }

    static func extensionValue(_ extension: FHIRJSONObject) -> (key: String, value: Any)? {
        let values = `extension`.filter { key, _ in
            key.hasPrefix("value") && key != "valueSet"
        }
        guard values.count == 1, let value = values.first else {
            return nil
        }
        return value
    }

    static func firstExtensionValue(
        _ element: FHIRJSONObject,
        url: String
    ) -> (key: String, value: Any)? {
        extensions(element, url: url).first.flatMap(extensionValue)
    }
}
