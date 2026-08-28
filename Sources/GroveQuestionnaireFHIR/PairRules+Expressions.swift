//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation

// Expression shape and execution paths deliberately preserve tri-state evaluation.
// swiftlint:disable cyclomatic_complexity discouraged_optional_boolean

extension PairRules {
    static func validateItemExpressionShapes(
        _ items: [FHIRJSONObject],
        path: String,
        targetConstraintKeys: inout Set<String>,
        issues: inout [ValidationIssue]
    ) {
        for (index, item) in items.enumerated() {
            let itemPath = "\(path)[\(index)]"
            if !(item["enableWhen"] as? [FHIRJSONObject] ?? []).isEmpty,
               !extensions(item, url: URL.enableWhenExpression).isEmpty {
                issues.append(.init(
                    code: .expressionShape,
                    path: itemPath,
                    message: "Use either enableWhen or enableWhenExpression, not both."
                ))
            }
            validateExpressionScope(
                item,
                path: itemPath,
                targetConstraintKeys: &targetConstraintKeys,
                issues: &issues
            )
            validateItemExpressionShapes(
                item["item"] as? [FHIRJSONObject] ?? [],
                path: "\(itemPath).item",
                targetConstraintKeys: &targetConstraintKeys,
                issues: &issues
            )
        }
    }

    static func validateExpressionScope(
        _ element: FHIRJSONObject,
        path: String,
        targetConstraintKeys: inout Set<String>,
        issues: inout [ValidationIssue]
    ) {
        var variableNames: Set<String> = []
        for (index, expressionExtension) in (element["extension"] as? [FHIRJSONObject] ?? []).enumerated() {
            guard let url = expressionExtension["url"] as? String else {
                continue
            }
            let extensionPath = "\(path).extension[\(index)]"
            if expressionURLs.contains(url) {
                let expression = extensionValue(expressionExtension)
                let requiresName = url == URL.variable
                guard expression?.key == "valueExpression",
                      let value = expression?.value as? FHIRJSONObject,
                      expressionIsValid(value, requireName: requiresName) else {
                    issues.append(.init(
                        code: .expressionShape,
                        path: extensionPath,
                        message: "Expression must contain the required non-empty FHIRPath fields."
                    ))
                    continue
                }
                if requiresName, let name = value["name"] as? String {
                    if !validExpressionName(name) || reservedVariables.contains(name) {
                        issues.append(.init(
                            code: .expressionShape,
                            path: "\(extensionPath).valueExpression.name",
                            message: "Expression variable name '\(name)' is invalid or reserved."
                        ))
                    } else if !variableNames.insert(name).inserted {
                        issues.append(.init(
                            code: .expressionShape,
                            path: "\(extensionPath).valueExpression.name",
                            message: "Expression variable name '\(name)' is duplicated in this scope."
                        ))
                    }
                }
            }
            if url == URL.targetConstraint {
                validateTargetConstraintShape(
                    expressionExtension,
                    path: extensionPath,
                    targetConstraintKeys: &targetConstraintKeys,
                    issues: &issues
                )
            }
        }
    }

    static func expressionIsValid(
        _ expression: FHIRJSONObject,
        requireName: Bool
    ) -> Bool {
        guard expression["language"] as? String == "text/fhirpath",
              let body = expression["expression"] as? String,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if requireName {
            guard let name = expression["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        return true
    }

    static func validExpressionName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter else {
            return false
        }
        return name.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func validateTargetConstraintShape(
        _ constraint: FHIRJSONObject,
        path: String,
        targetConstraintKeys: inout Set<String>,
        issues: inout [ValidationIssue]
    ) {
        let parts = Dictionary(
            (constraint["extension"] as? [FHIRJSONObject] ?? []).compactMap { part in
                (part["url"] as? String).map { ($0, part) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let key = parts["key"]?["valueId"] as? String
        if key?.isEmpty != false {
            issues.append(.init(
                code: .expressionShape,
                path: path,
                message: "targetConstraint requires a non-empty key."
            ))
        } else if let key, !targetConstraintKeys.insert(key).inserted {
            issues.append(.init(
                code: .expressionShape,
                path: path,
                message: "targetConstraint key '\(key)' is not unique."
            ))
        }
        if !["error", "warning"].contains(parts["severity"]?["valueCode"] as? String) {
            issues.append(.init(
                code: .expressionShape,
                path: path,
                message: "targetConstraint severity must be error or warning."
            ))
        }
        guard let human = parts["human"]?["valueString"] as? String,
              !human.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            issues.append(.init(
                code: .expressionShape,
                path: path,
                message: "targetConstraint requires non-empty human guidance."
            ))
            validateTargetExpression(parts["expression"], path: path, issues: &issues)
            return
        }
        validateTargetExpression(parts["expression"], path: path, issues: &issues)
    }

    static func validateTargetExpression(
        _ part: FHIRJSONObject?,
        path: String,
        issues: inout [ValidationIssue]
    ) {
        guard let expression = part?["valueExpression"] as? FHIRJSONObject,
              expressionIsValid(expression, requireName: false) else {
            issues.append(.init(
                code: .expressionShape,
                path: path,
                message: "targetConstraint requires a non-empty FHIRPath expression."
            ))
            return
        }
    }
}


extension PairContext {
    // Core enableWhen has one explicit branch for every R4 operator.
    // swiftlint:disable:next cyclomatic_complexity
    func evaluateEnableWhen(_ definition: FHIRJSONObject) -> Bool? {
        let conditions = definition["enableWhen"] as? [FHIRJSONObject] ?? []
        guard !conditions.isEmpty else {
            return true
        }
        var outcomes: [Bool] = []
        for condition in conditions {
            let values = allAnswers[condition["question"] as? String ?? ""] ?? []
            let expected = condition.filter { $0.key.hasPrefix("answer") }
            guard expected.count == 1, let expectedValue = expected.first?.value else {
                return nil
            }
            switch condition["operator"] as? String {
            case "exists":
                guard let expected = PairRules.boolean(expectedValue) else {
                    return nil
                }
                outcomes.append((!values.isEmpty) == expected)
            case "=":
                outcomes.append(values.contains { PairRules.valuesEqual($0, expectedValue) })
            case "!=":
                outcomes.append(values.contains { !PairRules.valuesEqual($0, expectedValue) })
            case ">", "<", ">=", "<=":
                guard let operation = condition["operator"] as? String else {
                    return nil
                }
                var comparisons: [Bool] = []
                for value in values {
                    guard let comparison = PairRules.compare(value, expectedValue) else {
                        return nil
                    }
                    let outcome = switch operation {
                    case ">": comparison == .orderedDescending
                    case "<": comparison == .orderedAscending
                    case ">=": comparison != .orderedAscending
                    default: comparison != .orderedDescending
                    }
                    comparisons.append(outcome)
                }
                outcomes.append(comparisons.contains(true))
            default:
                return nil
            }
        }
        return definition["enableBehavior"] as? String == "any"
            ? outcomes.contains(true)
            : outcomes.allSatisfy { $0 }
    }

    mutating func requireTargetConstraintEvaluation(
        in element: FHIRJSONObject,
        path: String
    ) {
        guard completed else {
            return
        }
        for constraint in PairRules.extensions(
            element,
            url: PairRules.URL.targetConstraint
        ) {
            evaluateTargetConstraint(constraint, path: path)
        }
        for (index, item) in (element["item"] as? [FHIRJSONObject] ?? []).enumerated() {
            let linkID = item["linkId"] as? String ?? "[\(index)]"
            requireTargetConstraintEvaluation(
                in: item,
                path: "\(path).item[\(linkID)]"
            )
        }
    }

    private mutating func evaluateTargetConstraint(
        _ constraint: FHIRJSONObject,
        path: String
    ) {
        let parts = Dictionary(
            (constraint["extension"] as? [FHIRJSONObject] ?? []).compactMap { part in
                (part["url"] as? String).map { ($0, part) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let severity: ValidationIssue.Severity =
            parts["severity"]?["valueCode"] as? String == "warning" ? .warning : .error
        let key = parts["key"]?["valueId"] as? String ?? "targetConstraint"
        let expression = (parts["expression"]?["valueExpression"] as? FHIRJSONObject)?["expression"] as? String
        guard let expressionEvaluator else {
            issues.append(.init(
                severity: severity,
                code: .expressionEngineRequired,
                path: path,
                message: "A FHIRPath engine must evaluate target constraint '\(key)'."
            ))
            return
        }
        do {
            guard let expression,
                  try expressionEvaluator.evaluate(expression, path: path) == true else {
                issues.append(.init(
                    severity: severity,
                    code: .targetConstraint,
                    path: path,
                    message: parts["human"]?["valueString"] as? String
                        ?? "Target constraint '\(key)' did not pass."
                ))
                return
            }
        } catch {
            issues.append(.init(
                severity: severity,
                code: .expressionEvaluation,
                path: path,
                message: "Target constraint '\(key)' failed to evaluate: \(error)"
            ))
        }
    }
}
