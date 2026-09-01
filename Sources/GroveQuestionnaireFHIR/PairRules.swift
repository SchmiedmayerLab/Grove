//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4

// Core pair orchestration and response-tree traversal stay together; domain validators live in focused extensions.
// `Bool?` represents enabled/disabled/indeterminate, and the bound rule table uses a
// three-field tuple to remain visibly aligned with the normative Python implementation.
// swiftlint:disable cyclomatic_complexity discouraged_optional_boolean file_types_order


typealias FHIRJSONObject = [String: Any]


enum PairRules {
    enum URL {
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
    static let expressionURLs: Set<String> = [
        URL.variable,
        URL.enableWhenExpression,
        URL.initialExpression,
        URL.calculatedExpression
    ]
    static let reservedVariables: Set<String> = [
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
    static let literalReferenceTypePattern = try? NSRegularExpression(
        pattern: #"(?:^|/)([A-Z][A-Za-z0-9]*)/[^/?#]+(?:/_history/[^/?#]+)?$"#
    )

    static let answerTypes: [String: Set<String>] = [
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
        valueSets: [ModelsR4.ValueSet],
        expressionEvaluator: PairExpressionEvaluator?
    ) -> [ValidationIssue] {
        do {
            return issues(
                questionnaire: try object(questionnaire),
                response: try object(response),
                valueSets: try valueSets.map(object),
                expressionEvaluator: expressionEvaluator
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
            throw ContractError.invalidQuestionnaireCanonical("non-object FHIR JSON")
        }
        return object
    }

    // Validation is accumulated before one deterministic sort so callers can compare reports.
    // swiftlint:disable:next function_body_length
    private static func issues(
        questionnaire: FHIRJSONObject,
        response: FHIRJSONObject,
        valueSets: [FHIRJSONObject],
        expressionEvaluator: PairExpressionEvaluator?
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        validateProfile(
            in: questionnaire,
            expected: Profile.groveQuestionnaire.value?.url.absoluteString,
            code: .questionnaireProfile,
            path: "Questionnaire.meta.profile",
            issues: &issues
        )
        validateProfile(
            in: response,
            expected: Profile.groveQuestionnaireResponse.value?.url.absoluteString,
            code: .responseProfile,
            path: "QuestionnaireResponse.meta.profile",
            issues: &issues
        )

        let questionnaireURL = questionnaire["url"] as? String ?? ""
        let questionnaireVersion = questionnaire["version"] as? String ?? ""
        let expectedCanonical = "\(questionnaireURL)|\(questionnaireVersion)"
        if !ContractRules.isValidQuestionnaireURL(questionnaireURL)
            || !ContractRules.isSemanticVersion(questionnaireVersion) {
            issues.append(.init(
                code: .questionnaireCanonical,
                path: "Questionnaire.url",
                message: "Questionnaire requires an exact HTTP(S) canonical URL and Semantic Versioning 2.0.0 version."
            ))
        }
        if response["questionnaire"] as? String != expectedCanonical {
            issues.append(.init(
                code: .questionnaireCanonical,
                path: "QuestionnaireResponse.questionnaire",
                message: "Expected the exact versioned canonical '\(expectedCanonical)'."
            ))
        }
        validateSubjectType(questionnaire: questionnaire, response: response, issues: &issues)
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
            expressionEvaluator: expressionEvaluator,
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

struct PairContext {
    let allDefinitionIDs: Set<String>
    let allAnswers: [String: [Any]]
    let resolver: ValueSetResolver
    let completed: Bool
    let expressionEvaluator: PairExpressionEvaluator?
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
            var enabled = evaluateEnableWhen(definition)
            let expressionEnablement = PairRules.extensions(
                definition,
                url: PairRules.URL.enableWhenExpression
            ).first
            if let expressionEnablement,
               let expression = PairRules.expressionString(from: expressionEnablement) {
                if let expressionEvaluator {
                    do {
                        enabled = try expressionEvaluator.evaluate(
                            expression,
                            path: "\(path).\(linkID)"
                        )
                    } catch {
                        enabled = nil
                        issues.append(.init(
                            code: .expressionEvaluation,
                            path: path,
                            message: "enableWhenExpression for '\(linkID)' failed: \(error)"
                        ))
                    }
                } else if completed {
                    enabled = nil
                    issues.append(.init(
                        code: .expressionEngineRequired,
                        path: path,
                        message: "Completed response requires FHIRPath enablement evaluation for '\(linkID)'."
                    ))
                }
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
    mutating func validateItem(
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
        } else if PairRules.answerTypes[itemType] != nil {
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
    }
}
