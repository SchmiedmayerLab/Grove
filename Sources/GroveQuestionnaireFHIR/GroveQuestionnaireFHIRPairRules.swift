//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreFoundation
import Foundation
import GroveFHIRContract
import ModelsR4

// This file intentionally keeps the IG companion algorithm in one reviewable order.
// `Bool?` represents enabled/disabled/indeterminate, and the bound rule table uses a
// three-field tuple to remain visibly aligned with the normative Python implementation.
// swiftlint:disable conditional_returns_on_newline cyclomatic_complexity discouraged_optional_boolean
// swiftlint:disable file_length file_types_order large_tuple multiline_function_chains


private typealias FHIRJSONObject = [String: Any]
typealias ValidationIssue = GroveQuestionnaireFHIRValidationIssue


enum GroveQuestionnaireFHIRPairRules {
    fileprivate enum URL {
        static let variable = "http://hl7.org/fhir/StructureDefinition/variable"
        static let targetConstraint = "http://hl7.org/fhir/StructureDefinition/targetConstraint"
        static let enableWhenExpression =
            "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression"
        static let initialExpression =
            "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression"
        static let calculatedExpression =
            "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression"
        static let minLength = "http://hl7.org/fhir/StructureDefinition/minLength"
        static let minValue = "http://hl7.org/fhir/StructureDefinition/minValue"
        static let maxValue = "http://hl7.org/fhir/StructureDefinition/maxValue"
        static let minQuantity =
            "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity"
        static let maxQuantity =
            "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity"
        static let maxDecimalPlaces = "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces"
        static let unitOption = "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"
        static let unitValueSet = "http://hl7.org/fhir/StructureDefinition/questionnaire-unitValueSet"
        static let minOccurs = "http://hl7.org/fhir/StructureDefinition/questionnaire-minOccurs"
        static let maxOccurs = "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs"
        static let mimeType = "http://hl7.org/fhir/StructureDefinition/mimeType"
        static let maxSize = "http://hl7.org/fhir/StructureDefinition/maxSize"
        static let optionExclusive =
            "http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive"
    }

    private static let completedStatuses: Set<String> = ["amended", "completed"]
    private static let expressionURLs: Set<String> = [
        URL.variable,
        URL.enableWhenExpression,
        URL.initialExpression,
        URL.calculatedExpression
    ]
    private static let reservedVariables: Set<String> = [
        "context",
        "definition",
        "loinc",
        "qitem",
        "questionnaire",
        "resource",
        "rootResource",
        "sct",
        "target",
        "ucum"
    ]

    fileprivate static let answerTypes: [String: Set<String>] = [
        "boolean": ["valueBoolean"],
        "decimal": ["valueDecimal"],
        "integer": ["valueInteger"],
        "date": ["valueDate"],
        "dateTime": ["valueDateTime"],
        "time": ["valueTime"],
        "string": ["valueString"],
        "text": ["valueString"],
        "url": ["valueUri"],
        "choice": ["valueCoding"],
        "open-choice": ["valueCoding", "valueString"],
        "attachment": ["valueAttachment"],
        "quantity": ["valueQuantity"]
    ]

    static func issues(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet]
    ) -> [ValidationIssue] {
        do {
            return issues(
                questionnaire: try object(questionnaire),
                response: try object(response),
                valueSets: try valueSets.map(object)
            )
        } catch {
            return [
                .init(
                    code: .serialization,
                    path: "Questionnaire/QuestionnaireResponse",
                    message: "Unable to serialize the FHIR validation inputs: \(error)"
                )
            ]
        }
    }

    private static func object(_ resource: some Encodable) throws -> FHIRJSONObject {
        let data = try JSONEncoder().encode(resource)
        guard let object = try JSONSerialization.jsonObject(with: data) as? FHIRJSONObject else {
            throw GroveQuestionnaireFHIRContractError.invalidQuestionnaireCanonical("non-object FHIR JSON")
        }
        return object
    }

    // Validation is accumulated before one deterministic sort so callers can compare reports.
    // swiftlint:disable:next function_body_length
    private static func issues(
        questionnaire: FHIRJSONObject,
        response: FHIRJSONObject,
        valueSets: [FHIRJSONObject]
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        validateProfile(
            in: questionnaire,
            expected: GroveFHIRProfile.groveQuestionnaire.value?.url.absoluteString,
            code: .questionnaireProfile,
            path: "Questionnaire.meta.profile",
            issues: &issues
        )
        validateProfile(
            in: response,
            expected: GroveFHIRProfile.groveQuestionnaireResponse.value?.url.absoluteString,
            code: .responseProfile,
            path: "QuestionnaireResponse.meta.profile",
            issues: &issues
        )

        let questionnaireURL = questionnaire["url"] as? String ?? ""
        let questionnaireVersion = questionnaire["version"] as? String ?? ""
        let expectedCanonical = "\(questionnaireURL)|\(questionnaireVersion)"
        if response["questionnaire"] as? String != expectedCanonical {
            issues.append(.init(
                code: .questionnaireCanonical,
                path: "QuestionnaireResponse.questionnaire",
                message: "Expected the exact versioned canonical '\(expectedCanonical)'."
            ))
        }
        if response["status"] as? String == "entered-in-error" {
            issues.append(.init(
                code: .responseEnteredInError,
                path: "QuestionnaireResponse.status",
                message: "An entered-in-error response must not be accepted as answer data."
            ))
        }
        if !isCompleteIdentifier(response["identifier"]) {
            issues.append(.init(
                code: .responseIdentifier,
                path: "QuestionnaireResponse.identifier",
                message: "A complete business identifier with system and value is required."
            ))
        }

        var targetConstraintKeys: Set<String> = []
        validateExpressionScope(
            questionnaire,
            path: "Questionnaire",
            targetConstraintKeys: &targetConstraintKeys,
            issues: &issues
        )
        validateItemExpressionShapes(
            questionnaire["item"] as? [FHIRJSONObject] ?? [],
            path: "Questionnaire.item",
            targetConstraintKeys: &targetConstraintKeys,
            issues: &issues
        )

        let definitions = questionnaire["item"] as? [FHIRJSONObject] ?? []
        var allDefinitionIDs: Set<String> = []
        collectDefinitionIDs(definitions, into: &allDefinitionIDs)
        var context = PairContext(
            allDefinitionIDs: allDefinitionIDs,
            allAnswers: questionnaireAnswerValues(response),
            resolver: .init(valueSets: valueSets),
            completed: completedStatuses.contains(response["status"] as? String ?? ""),
            issues: issues
        )
        context.validateContainer(
            definitions: definitions,
            responses: response["item"] as? [FHIRJSONObject] ?? [],
            path: "QuestionnaireResponse.item"
        )
        context.requireTargetConstraintEvaluation(
            in: questionnaire,
            path: "QuestionnaireResponse"
        )
        return context.issues.sorted {
            ($0.path, $0.code.rawValue, $0.severity.rawValue, $0.message)
                < ($1.path, $1.code.rawValue, $1.severity.rawValue, $1.message)
        }
    }
}


extension GroveQuestionnaireFHIRPairRules {
    private static func validateProfile(
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
                message: "Expected exactly the Grove 0.2 profile claim."
            ))
            return
        }
    }

    private static func isCompleteIdentifier(_ value: Any?) -> Bool {
        guard let identifier = value as? FHIRJSONObject,
              let system = identifier["system"] as? String,
              !system.isEmpty,
              let identifierValue = identifier["value"] as? String,
              !identifierValue.isEmpty else {
            return false
        }
        return Foundation.URL(string: system)?.scheme != nil
    }

    private static func collectDefinitionIDs(
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

    fileprivate static func extensions(
        _ element: FHIRJSONObject,
        url: String
    ) -> [FHIRJSONObject] {
        (element["extension"] as? [FHIRJSONObject] ?? []).filter { $0["url"] as? String == url }
    }

    fileprivate static func extensionValue(_ extension: FHIRJSONObject) -> (key: String, value: Any)? {
        let values = `extension`.filter { key, _ in
            key.hasPrefix("value") && key != "valueSet"
        }
        guard values.count == 1, let value = values.first else {
            return nil
        }
        return value
    }

    fileprivate static func firstExtensionValue(
        _ element: FHIRJSONObject,
        url: String
    ) -> (key: String, value: Any)? {
        extensions(element, url: url).first.flatMap(extensionValue)
    }
}


extension GroveQuestionnaireFHIRPairRules {
    private static func validateItemExpressionShapes(
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

    private static func validateExpressionScope(
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

    private static func expressionIsValid(
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

    private static func validExpressionName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter else {
            return false
        }
        return name.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private static func validateTargetConstraintShape(
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

    private static func validateTargetExpression(
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


private struct PairContext {
    let allDefinitionIDs: Set<String>
    let allAnswers: [String: [Any]]
    let resolver: GroveQuestionnaireFHIRValueSetResolver
    let completed: Bool
    var issues: [ValidationIssue]

    // The explicit recursion mirrors QuestionnaireResponse's group and answer contexts.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func validateContainer(
        definitions: [FHIRJSONObject],
        responses: [FHIRJSONObject],
        path: String
    ) {
        var expected: [String: FHIRJSONObject] = [:]
        for definition in definitions {
            if let linkID = definition["linkId"] as? String, expected[linkID] == nil {
                expected[linkID] = definition
            }
        }
        var actual: [String: [(value: FHIRJSONObject, path: String)]] = [:]
        for (index, response) in responses.enumerated() {
            let itemPath = "\(path)[\(index)]"
            guard let linkID = response["linkId"] as? String,
                  expected[linkID] != nil else {
                let linkID = response["linkId"] as? String ?? ""
                issues.append(.init(
                    code: allDefinitionIDs.contains(linkID) ? .itemMisplaced : .itemUnknown,
                    path: "\(itemPath).linkId",
                    message: "Item '\(linkID)' is not valid in this response context."
                ))
                continue
            }
            actual[linkID, default: []].append((response, itemPath))
        }

        for (linkID, occurrences) in actual where occurrences.count > 1 {
            issues.append(.init(
                code: .itemDuplicate,
                path: path,
                message: "Item '\(linkID)' appears more than once in one response context."
            ))
        }

        for definition in definitions {
            guard let linkID = definition["linkId"] as? String else {
                continue
            }
            let enabled = evaluateEnableWhen(definition)
            let hasExpressionEnablement = !GroveQuestionnaireFHIRPairRules.extensions(
                definition,
                url: GroveQuestionnaireFHIRPairRules.URL.enableWhenExpression
            ).isEmpty
            if hasExpressionEnablement, completed {
                issues.append(.init(
                    code: .expressionEngineRequired,
                    path: path,
                    message: "Completed response requires FHIRPath enablement evaluation for '\(linkID)'."
                ))
            }
            if enabled == nil, completed {
                issues.append(.init(
                    code: .enableWhenEvaluation,
                    path: path,
                    message: "Cannot evaluate enableWhen for '\(linkID)'."
                ))
            }
            let occurrences = actual[linkID] ?? []
            if enabled == false, let first = occurrences.first {
                issues.append(.init(
                    code: .itemDisabled,
                    path: first.path,
                    message: "Disabled item '\(linkID)' must not be present."
                ))
            }
            if completed,
               definition["required"] as? Bool == true,
               enabled == true,
               occurrences.isEmpty {
                issues.append(.init(
                    code: .requiredItem,
                    path: path,
                    message: "Required enabled item '\(linkID)' is missing."
                ))
            }

            for occurrence in occurrences {
                validateItem(
                    definition: definition,
                    response: occurrence.value,
                    path: occurrence.path,
                    enabled: enabled
                )
            }
            if completed,
               enabled == true,
               definition["type"] as? String == "group",
               occurrences.isEmpty {
                validateContainer(
                    definitions: definition["item"] as? [FHIRJSONObject] ?? [],
                    responses: [],
                    path: "\(path).\(linkID).item"
                )
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private mutating func validateItem(
        definition: FHIRJSONObject,
        response: FHIRJSONObject,
        path: String,
        enabled: Bool?
    ) {
        if response["text"] as? String != definition["text"] as? String {
            issues.append(.init(
                code: .responseText,
                path: "\(path).text",
                message: "Response text must equal the Questionnaire item text."
            ))
        }
        let itemType = definition["type"] as? String ?? ""
        let answers = response["answer"] as? [FHIRJSONObject] ?? []
        if ["group", "display"].contains(itemType), !answers.isEmpty {
            issues.append(.init(
                code: .answerType,
                path: "\(path).answer",
                message: "A \(itemType) item cannot carry answers."
            ))
        } else if GroveQuestionnaireFHIRPairRules.answerTypes[itemType] != nil {
            validateAnswerConstraints(definition: definition, answers: answers, path: path)
            if completed,
               definition["required"] as? Bool == true,
               enabled == true,
               answers.isEmpty {
                issues.append(.init(
                    code: .requiredItem,
                    path: path,
                    message: "A required enabled item must carry an answer."
                ))
            }
        }

        let directChildren = response["item"] as? [FHIRJSONObject] ?? []
        if !directChildren.isEmpty, itemType != "group" {
            issues.append(.init(
                code: .itemNesting,
                path: "\(path).item",
                message: "Question children belong beneath the answer that supplies their context."
            ))
        }
        if itemType == "group" {
            validateContainer(
                definitions: definition["item"] as? [FHIRJSONObject] ?? [],
                responses: directChildren,
                path: "\(path).item"
            )
        } else {
            for (index, answer) in answers.enumerated() {
                validateContainer(
                    definitions: definition["item"] as? [FHIRJSONObject] ?? [],
                    responses: answer["item"] as? [FHIRJSONObject] ?? [],
                    path: "\(path).answer[\(index)].item"
                )
            }
        }
        requireTargetConstraintEvaluation(in: definition, path: path)
    }
}


extension PairContext {
    // Every family in the IG's deterministic answer checker is handled in one pass.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private mutating func validateAnswerConstraints(
        definition: FHIRJSONObject,
        answers: [FHIRJSONObject],
        path: String
    ) {
        let expectedTypes = GroveQuestionnaireFHIRPairRules.answerTypes[
            definition["type"] as? String ?? ""
        ] ?? []
        var selectedOptions: [FHIRJSONObject] = []
        for (index, answer) in answers.enumerated() {
            let answerPath = "\(path).answer[\(index)]"
            guard let answerValue = GroveQuestionnaireFHIRPairRules.answerValue(answer),
                  expectedTypes.contains(answerValue.key) else {
                issues.append(.init(
                    code: .answerType,
                    path: answerPath,
                    message: "Answer type does not match Questionnaire item type."
                ))
                continue
            }
            let options = definition["answerOption"] as? [FHIRJSONObject] ?? []
            if !options.isEmpty,
               ["valueCoding", "valueString", "valueInteger", "valueDate", "valueTime"]
                .contains(answerValue.key) {
                let selected = GroveQuestionnaireFHIRPairRules.selectedInlineOption(
                    definition,
                    value: answerValue.value
                )
                let isOpenText = definition["type"] as? String == "open-choice"
                    && answerValue.key == "valueString"
                if selected == nil, !isOpenText {
                    issues.append(.init(
                        code: .answerOption,
                        path: answerPath,
                        message: "Answer is not one of the Questionnaire's inline answer options."
                    ))
                } else if let selected {
                    selectedOptions.append(selected)
                }
            }

            if let canonical = definition["answerValueSet"] as? String,
               answerValue.key == "valueCoding" {
                switch resolver.contains(canonical: canonical, coding: answerValue.value) {
                case .some(true):
                    break
                case .some(false):
                    issues.append(.init(
                        code: .answerValueSet,
                        path: answerPath,
                        message: "Coded answer is not in the referenced ValueSet."
                    ))
                case nil:
                    issues.append(.init(
                        code: .valueSetUnresolved,
                        path: answerPath,
                        message: "Cannot resolve and deterministically expand '\(canonical)'."
                    ))
                }
            }

            validateLength(definition: definition, answer: answerValue, path: answerPath)
            validateDecimalPlaces(definition: definition, answer: answerValue, path: answerPath)
            validateBounds(definition: definition, answer: answerValue, path: answerPath)
            validateUnit(definition: definition, answer: answerValue, path: answerPath)
            validateAttachment(definition: definition, answer: answerValue, path: answerPath)
        }

        let selectedExclusive = selectedOptions.contains { option in
            GroveQuestionnaireFHIRPairRules.extensions(
                option,
                url: GroveQuestionnaireFHIRPairRules.URL.optionExclusive
            ).contains {
                guard let value = GroveQuestionnaireFHIRPairRules.extensionValue($0) else {
                    return false
                }
                return value.key == "valueBoolean"
                    && GroveQuestionnaireFHIRPairRules.boolean(value.value) == true
            }
        }
        if selectedExclusive, answers.count > 1 {
            issues.append(.init(
                code: .optionExclusive,
                path: path,
                message: "An exclusive option cannot be combined with another answer."
            ))
        }
        if definition["repeats"] as? Bool != true, answers.count > 1 {
            issues.append(.init(
                code: .repeats,
                path: path,
                message: "A non-repeating item cannot carry multiple answers."
            ))
        }
        let minimum = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.minOccurs
        ).flatMap { GroveQuestionnaireFHIRPairRules.integer($0.value) }
        let maximum = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.maxOccurs
        ).flatMap { GroveQuestionnaireFHIRPairRules.integer($0.value) }
        if let minimum, answers.count < minimum {
            issues.append(.init(
                code: .answerOccurrence,
                path: path,
                message: "Answer count is below questionnaire-minOccurs."
            ))
        }
        if let maximum, answers.count > maximum {
            issues.append(.init(
                code: .answerOccurrence,
                path: path,
                message: "Answer count exceeds questionnaire-maxOccurs."
            ))
        }
    }

    private mutating func validateLength(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard ["valueString", "valueUri"].contains(answer.key),
              let value = answer.value as? String else {
            return
        }
        let length = value.unicodeScalars.count
        let minimum = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.minLength
        ).flatMap { GroveQuestionnaireFHIRPairRules.integer($0.value) }
        let maximum = GroveQuestionnaireFHIRPairRules.integer(definition["maxLength"])
        if let minimum, length < minimum {
            issues.append(.init(
                code: .answerLength,
                path: path,
                message: "Answer is shorter than minLength."
            ))
        }
        if let maximum, length > maximum {
            issues.append(.init(
                code: .answerLength,
                path: path,
                message: "Answer exceeds maxLength."
            ))
        }
    }

    private mutating func validateDecimalPlaces(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard answer.key == "valueDecimal",
              let maximum = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
                definition,
                url: GroveQuestionnaireFHIRPairRules.URL.maxDecimalPlaces
              ).flatMap({ GroveQuestionnaireFHIRPairRules.integer($0.value) }),
              let actual = GroveQuestionnaireFHIRPairRules.decimalPlaces(answer.value),
              actual > maximum else {
            return
        }
        issues.append(.init(
            code: .answerDecimalPlaces,
            path: path,
            message: "Answer exceeds maxDecimalPlaces."
        ))
    }

    private mutating func validateBounds(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        let bounds: [(url: String, minimum: Bool, code: ValidationIssue.Code)] = [
            (GroveQuestionnaireFHIRPairRules.URL.minValue, true, .answerValueBound),
            (GroveQuestionnaireFHIRPairRules.URL.maxValue, false, .answerValueBound),
            (GroveQuestionnaireFHIRPairRules.URL.minQuantity, true, .answerQuantityBound),
            (GroveQuestionnaireFHIRPairRules.URL.maxQuantity, false, .answerQuantityBound)
        ]
        for bound in bounds {
            guard let value = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
                definition,
                url: bound.url
            )?.value else {
                continue
            }
            let valid = bound.minimum
                ? GroveQuestionnaireFHIRPairRules.lessThanOrEqual(value, answer.value)
                : GroveQuestionnaireFHIRPairRules.lessThanOrEqual(answer.value, value)
            if valid != true {
                issues.append(.init(
                    code: bound.code,
                    path: path,
                    message: "Answer violates a bound or uses an incomparable unit."
                ))
            }
        }
    }

    private mutating func validateUnit(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard answer.key == "valueQuantity",
              let quantity = answer.value as? FHIRJSONObject else {
            return
        }
        let options = GroveQuestionnaireFHIRPairRules.extensions(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.unitOption
        ).compactMap(GroveQuestionnaireFHIRPairRules.extensionValue)
            .map(\.value)
        if !options.isEmpty,
           !options.contains(where: { GroveQuestionnaireFHIRPairRules.valuesEqual(quantity, $0) }) {
            issues.append(.init(
                code: .answerUnit,
                path: path,
                message: "Quantity unit is not one of questionnaire-unitOption."
            ))
        }
        guard let canonical = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.unitValueSet
        )?.value as? String else {
            return
        }
        let coding: FHIRJSONObject = ["system": quantity["system"] as Any, "code": quantity["code"] as Any]
        switch resolver.contains(canonical: canonical, coding: coding) {
        case .some(true):
            break
        case .some(false):
            issues.append(.init(
                code: .answerUnit,
                path: path,
                message: "Quantity unit is not certified by questionnaire-unitValueSet."
            ))
        case nil:
            issues.append(.init(
                code: .valueSetUnresolved,
                path: path,
                message: "Cannot resolve and deterministically expand unit ValueSet '\(canonical)'."
            ))
        }
    }

    private mutating func validateAttachment(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard answer.key == "valueAttachment",
              let attachment = answer.value as? FHIRJSONObject else {
            return
        }
        let allowedTypes = Set(GroveQuestionnaireFHIRPairRules.extensions(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.mimeType
        ).compactMap(GroveQuestionnaireFHIRPairRules.extensionValue).compactMap { $0.value as? String })
        let contentTypeAllowed = (attachment["contentType"] as? String).map(allowedTypes.contains) ?? false
        if !allowedTypes.isEmpty, !contentTypeAllowed {
            issues.append(.init(
                code: .answerAttachment,
                path: path,
                message: "Attachment contentType is not allowed."
            ))
        }
        guard let maximum = GroveQuestionnaireFHIRPairRules.firstExtensionValue(
            definition,
            url: GroveQuestionnaireFHIRPairRules.URL.maxSize
        ).flatMap({ GroveQuestionnaireFHIRPairRules.decimal($0.value) }) else {
            return
        }
        guard let size = GroveQuestionnaireFHIRPairRules.decimal(attachment["size"]),
              size <= maximum else {
            issues.append(.init(
                code: .answerAttachment,
                path: path,
                message: "Attachment exceeds maxSize or does not declare size."
            ))
            return
        }
    }
}


extension PairContext {
    // Core enableWhen has one explicit branch for every R4 operator.
    // swiftlint:disable:next cyclomatic_complexity
    private func evaluateEnableWhen(_ definition: FHIRJSONObject) -> Bool? {
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
                guard let expected = GroveQuestionnaireFHIRPairRules.boolean(expectedValue) else {
                    return nil
                }
                outcomes.append((!values.isEmpty) == expected)
            case "=":
                outcomes.append(values.contains { GroveQuestionnaireFHIRPairRules.valuesEqual($0, expectedValue) })
            case "!=":
                outcomes.append(values.contains { !GroveQuestionnaireFHIRPairRules.valuesEqual($0, expectedValue) })
            case ">", "<", ">=", "<=":
                guard let operation = condition["operator"] as? String else {
                    return nil
                }
                var comparisons: [Bool] = []
                for value in values {
                    guard let comparison = GroveQuestionnaireFHIRPairRules.compare(value, expectedValue) else {
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
        for constraint in GroveQuestionnaireFHIRPairRules.extensions(
            element,
            url: GroveQuestionnaireFHIRPairRules.URL.targetConstraint
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
            issues.append(.init(
                severity: severity,
                code: .expressionEngineRequired,
                path: path,
                message: "A FHIRPath engine must evaluate target constraint '\(key)'."
            ))
        }
    }
}


extension GroveQuestionnaireFHIRPairRules {
    fileprivate static func answerValue(_ answer: FHIRJSONObject) -> (key: String, value: Any)? {
        let values = answer.filter { key, _ in
            key.hasPrefix("value") && answerTypes.values.contains { $0.contains(key) }
        }
        guard values.count == 1, let value = values.first else {
            return nil
        }
        return value
    }

    private static func questionnaireAnswerValues(_ response: FHIRJSONObject) -> [String: [Any]] {
        var values: [String: [Any]] = [:]
        collectResponseValues(
            response["item"] as? [FHIRJSONObject] ?? [],
            into: &values
        )
        return values
    }

    private static func collectResponseValues(
        _ items: [FHIRJSONObject],
        into values: inout [String: [Any]]
    ) {
        for item in items {
            let linkID = item["linkId"] as? String ?? ""
            if values[linkID] == nil {
                values[linkID] = []
            }
            for answer in item["answer"] as? [FHIRJSONObject] ?? [] {
                if let value = answerValue(answer)?.value {
                    values[linkID, default: []].append(value)
                }
                collectResponseValues(
                    answer["item"] as? [FHIRJSONObject] ?? [],
                    into: &values
                )
            }
            collectResponseValues(item["item"] as? [FHIRJSONObject] ?? [], into: &values)
        }
    }

    fileprivate static func selectedInlineOption(
        _ item: FHIRJSONObject,
        value: Any
    ) -> FHIRJSONObject? {
        (item["answerOption"] as? [FHIRJSONObject] ?? []).first { option in
            guard let candidate = extensionValue(option)?.value else {
                return false
            }
            return valuesEqual(value, candidate)
        }
    }

    fileprivate static func valuesEqual(_ left: Any, _ right: Any) -> Bool {
        if let leftQuantity = comparableQuantity(left),
           let rightQuantity = comparableQuantity(right) {
            return leftQuantity == rightQuantity
        }
        if let leftCoding = codingKey(left),
           let rightCoding = codingKey(right) {
            return leftCoding == rightCoding
        }
        if let leftDecimal = decimal(left), let rightDecimal = decimal(right) {
            return leftDecimal == rightDecimal
        }
        if let left = left as? String, let right = right as? String {
            return left == right
        }
        if let left = boolean(left), let right = boolean(right) {
            return left == right
        }
        guard JSONSerialization.isValidJSONObject(["value": left]),
              JSONSerialization.isValidJSONObject(["value": right]) else {
            return false
        }
        return (try? JSONSerialization.data(withJSONObject: ["value": left], options: [.sortedKeys]))
            == (try? JSONSerialization.data(withJSONObject: ["value": right], options: [.sortedKeys]))
    }

    fileprivate static func lessThanOrEqual(_ left: Any, _ right: Any) -> Bool? {
        if let left = decimal(left), let right = decimal(right) {
            return left <= right
        }
        if let left = left as? String, let right = right as? String {
            return left <= right
        }
        if let left = comparableQuantity(left), let right = comparableQuantity(right) {
            guard left.system == right.system, left.code == right.code else {
                return nil
            }
            return left.value <= right.value
        }
        return nil
    }

    fileprivate static func compare(_ left: Any, _ right: Any) -> ComparisonResult? {
        if let left = decimal(left), let right = decimal(right) {
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        }
        if let left = left as? String, let right = right as? String {
            return left.compare(right)
        }
        return nil
    }

    fileprivate static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return value as? Bool
        }
        return number.boolValue
    }

    fileprivate static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return value as? Int
        }
        let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        let integer = number.intValue
        guard decimal == Decimal(integer) else {
            return nil
        }
        return integer
    }

    fileprivate static func decimal(_ value: Any?) -> Decimal? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
                return nil
            }
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let string = value as? String {
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    fileprivate static func decimalPlaces(_ value: Any) -> Int? {
        guard let decimal = decimal(value) else {
            return nil
        }
        let string = NSDecimalNumber(decimal: decimal).stringValue
        guard let separator = string.firstIndex(of: ".") else {
            return 0
        }
        return string.distance(from: string.index(after: separator), to: string.endIndex)
    }

    private static func codingKey(_ value: Any) -> CodingIdentity? {
        guard let coding = value as? FHIRJSONObject,
              let code = coding["code"] as? String,
              !code.isEmpty else {
            return nil
        }
        return CodingIdentity(system: coding["system"] as? String, code: code)
    }

    private static func comparableQuantity(_ value: Any) -> QuantityIdentity? {
        guard let quantity = value as? FHIRJSONObject,
              let value = decimal(quantity["value"]),
              let system = quantity["system"] as? String,
              let code = quantity["code"] as? String else {
            return nil
        }
        return QuantityIdentity(value: value, system: system, code: code)
    }
}


private struct CodingIdentity: Equatable {
    // periphery:ignore - read by the synthesized Equatable; `codingKey` values are only ever compared
    let system: String?
    // periphery:ignore - read by the synthesized Equatable; `codingKey` values are only ever compared
    let code: String
}


private struct QuantityIdentity: Equatable {
    let value: Decimal
    let system: String
    let code: String
}


private struct GroveQuestionnaireFHIRValueSetResolver {
    private let resources: [String: FHIRJSONObject]

    init(valueSets: [FHIRJSONObject]) {
        var resources: [String: FHIRJSONObject] = [:]
        for valueSet in valueSets where valueSet["resourceType"] as? String == "ValueSet" {
            guard let url = valueSet["url"] as? String else {
                continue
            }
            resources[url] = valueSet
            if let version = valueSet["version"] as? String {
                resources["\(url)|\(version)"] = valueSet
            }
        }
        self.resources = resources
    }

    func contains(canonical: String, coding: Any) -> Bool? {
        guard let valueSet = resources[canonical],
              let coding = coding as? FHIRJSONObject,
              let code = coding["code"] as? String,
              !code.isEmpty else {
            return nil
        }
        let system = coding["system"] as? String
        let compose = valueSet["compose"] as? FHIRJSONObject
        for include in compose?["include"] as? [FHIRJSONObject] ?? [] {
            if include["filter"] != nil || include["valueSet"] != nil {
                return nil
            }
            guard include["system"] as? String == system else {
                continue
            }
            guard let concepts = include["concept"] as? [FHIRJSONObject] else {
                return nil
            }
            if concepts.contains(where: { $0["code"] as? String == code }) {
                return true
            }
        }
        let expansion = valueSet["expansion"] as? FHIRJSONObject
        if (expansion?["contains"] as? [FHIRJSONObject] ?? []).contains(where: {
            $0["system"] as? String == system && $0["code"] as? String == code
        }) {
            return true
        }
        return false
    }
}
