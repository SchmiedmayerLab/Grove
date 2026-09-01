//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing

// The parameterized corpus deliberately keeps JSON mutations adjacent to their expected
// rule families so it remains mechanically comparable with the IG's pair corpus.
// swiftlint:disable cyclomatic_complexity file_length function_body_length
// swiftlint:disable multiline_literal_brackets type_body_length


@Suite
struct GroveQuestionnaireFHIRPairRuleTests {
    private typealias JSONObject = [String: Any]

    enum AnswerRuleCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case minimumLength
        case maximumLength
        case decimalPlaces
        case minimumValue
        case maximumValue
        case minimumQuantity
        case maximumQuantity
        case unitOption
        case unresolvedUnitValueSet
        case attachmentMIMEType
        case attachmentSize
        case minimumOccurrence
        case maximumOccurrence
        case exclusiveOption

        var testDescription: String { rawValue }

        var expectedCode: ValidationIssue.Code {
            switch self {
            case .minimumLength, .maximumLength: .answerLength
            case .decimalPlaces: .answerDecimalPlaces
            case .minimumValue, .maximumValue: .answerValueBound
            case .minimumQuantity, .maximumQuantity: .answerQuantityBound
            case .unitOption: .answerUnit
            case .unresolvedUnitValueSet: .valueSetUnresolved
            case .attachmentMIMEType, .attachmentSize: .answerAttachment
            case .minimumOccurrence, .maximumOccurrence: .answerOccurrence
            case .exclusiveOption: .optionExclusive
            }
        }
    }

    enum ValueSetCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case member
        case nonmember
        case unresolved

        var testDescription: String { rawValue }
    }

    enum EnablementCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case enabled
        case disabledPresent
        case requiredMissing
        case indeterminate

        var testDescription: String { rawValue }
    }

    enum ConstraintLocation: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case root
        case item

        var testDescription: String { rawValue }
    }

    enum ExpressionShapeCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case emptyExpression
        case incompleteTargetConstraint
        case mixedEnablementForms

        var testDescription: String { rawValue }
    }

    @Test("Questionnaire subjectType matches a declared, literal, absolute, or contained target")
    func validatesResolvedSubjectType() throws {
        let validSubjects: [JSONObject] = [
            ["type": "Patient", "identifier": ["system": "https://example.org/patient", "value": "one"]],
            [
                "type": "http://hl7.org/fhir/StructureDefinition/Patient",
                "identifier": ["system": "https://example.org/patient", "value": "two"]
            ],
            ["reference": "Patient/one"],
            ["reference": "https://example.org/fhir/Patient/one/_history/2"],
            ["reference": "#patient"]
        ]
        for subject in validSubjects {
            var objects = try basePairObjects()
            objects.questionnaire["subjectType"] = ["Patient"]
            objects.response["subject"] = subject
            if subject["reference"] as? String == "#patient" {
                objects.response["contained"] = [["resourceType": "Patient", "id": "patient"]]
            }
            let pair = try decodePair(objects)
            let issues = PairValidator().issues(
                questionnaire: pair.questionnaire,
                response: pair.response
            )
            #expect(!issues.contains { $0.code == .subjectType })
        }
    }

    @Test("Questionnaire subjectType rejects mismatches, conflicts, and unresolved targets")
    func rejectsInvalidSubjectType() throws {
        let invalidSubjects: [JSONObject] = [
            ["type": "Practitioner", "reference": "Practitioner/one"],
            ["type": "Patient", "reference": "Practitioner/one"],
            ["type": "https://not-hl7.example/Patient", "reference": "Patient/one"],
            ["reference": "urn:uuid:78f7199c-ea39-4d68-9311-bdc1d25ad709"],
            ["reference": "#missing"]
        ]
        for subject in invalidSubjects {
            var objects = try basePairObjects()
            objects.questionnaire["subjectType"] = ["Patient"]
            objects.response["subject"] = subject
            let pair = try decodePair(objects)
            let issues = PairValidator().issues(
                questionnaire: pair.questionnaire,
                response: pair.response
            )
            #expect(issues.contains {
                $0.code == .subjectType && $0.path == "QuestionnaireResponse.subject"
            })
        }
    }

    @Test("The unmutated base pair is issue-free, so every mutation below is the cause")
    func basePairIsIssueFree() throws {
        let pair = try decodePair(try basePairObjects())
        let issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(issues.isEmpty)
    }

    @Test("Rejects every deterministic answer-constraint family", arguments: AnswerRuleCase.allCases)
    func rejectsAnswerConstraintFamily(testCase: AnswerRuleCase) throws {
        var objects = try basePairObjects()
        var definition = try question(in: objects.questionnaire)
        var response = try question(in: objects.response)

        switch testCase {
        case .minimumLength:
            definition["type"] = "string"
            definition["extension"] = [extensionJSON(minLength, "valueInteger", 3)]
            response["answer"] = [["valueString": "no"]]
        case .maximumLength:
            definition["type"] = "string"
            definition["maxLength"] = 2
            response["answer"] = [["valueString": "long"]]
        case .decimalPlaces:
            definition["type"] = "decimal"
            definition["extension"] = [extensionJSON(maxDecimalPlaces, "valueInteger", 2)]
            response["answer"] = [["valueDecimal": 1.234]]
        case .minimumValue:
            definition["type"] = "decimal"
            definition["extension"] = [extensionJSON(minValue, "valueDecimal", 2)]
            response["answer"] = [["valueDecimal": 1]]
        case .maximumValue:
            definition["type"] = "decimal"
            definition["extension"] = [extensionJSON(maxValue, "valueDecimal", 2)]
            response["answer"] = [["valueDecimal": 3]]
        case .minimumQuantity:
            definition["type"] = "quantity"
            definition["extension"] = [
                extensionJSON(minQuantity, "valueQuantity", quantity(value: 3, code: "kg"))
            ]
            response["answer"] = [["valueQuantity": quantity(value: 2, code: "kg")]]
        case .maximumQuantity:
            definition["type"] = "quantity"
            definition["extension"] = [
                extensionJSON(maxQuantity, "valueQuantity", quantity(value: 3, code: "kg"))
            ]
            response["answer"] = [["valueQuantity": quantity(value: 4, code: "kg")]]
        case .unitOption:
            definition["type"] = "quantity"
            definition["extension"] = [
                extensionJSON(unitOption, "valueCoding", coding(system: Self.ucum, code: "kg"))
            ]
            response["answer"] = [["valueQuantity": quantity(value: 2, code: "g")]]
        case .unresolvedUnitValueSet:
            definition["type"] = "quantity"
            definition["extension"] = [
                extensionJSON(unitValueSet, "valueCanonical", "https://example.org/fhir/ValueSet/units|1.0.0")
            ]
            response["answer"] = [["valueQuantity": quantity(value: 2, code: "kg")]]
        case .attachmentMIMEType:
            definition["type"] = "attachment"
            definition["extension"] = [extensionJSON(mimeType, "valueCode", "image/png")]
            response["answer"] = [[
                "valueAttachment": ["contentType": "application/pdf", "size": 10]
            ]]
        case .attachmentSize:
            definition["type"] = "attachment"
            definition["extension"] = [extensionJSON(maxSize, "valueDecimal", 5)]
            response["answer"] = [[
                "valueAttachment": ["contentType": "image/png", "size": 10]
            ]]
        case .minimumOccurrence:
            definition["type"] = "choice"
            definition["repeats"] = true
            definition["extension"] = [extensionJSON(minOccurs, "valueInteger", 2)]
            response["answer"] = [["valueCoding": coding(code: "one")]]
        case .maximumOccurrence:
            definition["type"] = "choice"
            definition["repeats"] = true
            definition["extension"] = [extensionJSON(maxOccurs, "valueInteger", 1)]
            response["answer"] = [
                ["valueCoding": coding(code: "one")],
                ["valueCoding": coding(code: "two")]
            ]
        case .exclusiveOption:
            definition["type"] = "choice"
            definition["repeats"] = true
            definition["answerOption"] = [
                [
                    "valueCoding": coding(code: "none"),
                    "extension": [extensionJSON(optionExclusive, "valueBoolean", true)]
                ],
                ["valueCoding": coding(code: "other")]
            ]
            response["answer"] = [
                ["valueCoding": coding(code: "none")],
                ["valueCoding": coding(code: "other")]
            ]
        }

        try replaceQuestion(in: &objects.questionnaire, with: definition)
        try replaceQuestion(in: &objects.response, with: response)
        let pair = try decodePair(objects)
        let issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(issues.contains { $0.code == testCase.expectedCode })
    }

    @Test("Resolves an exact ValueSet or fails closed", arguments: ValueSetCase.allCases)
    func validatesAnswerValueSet(testCase: ValueSetCase) throws {
        var objects = try basePairObjects()
        var definition = try question(in: objects.questionnaire)
        var response = try question(in: objects.response)
        let canonical = "https://example.org/fhir/ValueSet/answers|1.0.0"
        definition["type"] = "choice"
        definition["answerValueSet"] = canonical
        response["answer"] = [[
            "valueCoding": coding(code: testCase == .nonmember ? "other" : "allowed")
        ]]
        try replaceQuestion(in: &objects.questionnaire, with: definition)
        try replaceQuestion(in: &objects.response, with: response)

        let pair = try decodePair(objects)
        let valueSets = testCase == .unresolved ? [] : [try valueSet()]
        let issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response,
            valueSets: valueSets
        )
        switch testCase {
        case .member:
            #expect(!issues.contains { [.answerValueSet, .valueSetUnresolved].contains($0.code) })
        case .nonmember:
            #expect(issues.contains { $0.code == .answerValueSet })
        case .unresolved:
            #expect(issues.contains { $0.code == .valueSetUnresolved })
        }
    }

    @Test
    func semanticCodingAndQuantityComparisonsIgnoreDisplaysButPreserveComputableIdentity() throws {
        var objects = try basePairObjects()
        var definition = try question(in: objects.questionnaire)
        var response = try question(in: objects.response)
        definition["type"] = "choice"
        definition["answerOption"] = [[
            "valueCoding": coding(code: "allowed", version: "source-version", display: "Publisher display")
        ]]
        response["answer"] = [[
            "valueCoding": coding(code: "allowed", version: "receiver-version", display: "Localized display")
        ]]
        try replaceQuestion(in: &objects.questionnaire, with: definition)
        try replaceQuestion(in: &objects.response, with: response)
        var pair = try decodePair(objects)
        var issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(!issues.contains { $0.code == .answerOption })

        definition["type"] = "quantity"
        definition.removeValue(forKey: "answerOption")
        definition["extension"] = [
            extensionJSON(unitOption, "valueCoding", coding(system: Self.ucum, code: "kg")),
            extensionJSON(minQuantity, "valueQuantity", quantity(value: 1, code: "kg")),
            extensionJSON(maxQuantity, "valueQuantity", quantity(value: 3, code: "kg"))
        ]
        response["answer"] = [[
            "valueQuantity": quantity(value: 2, code: "kg", unit: "kilograms")
        ]]
        try replaceQuestion(in: &objects.questionnaire, with: definition)
        try replaceQuestion(in: &objects.response, with: response)
        pair = try decodePair(objects)
        issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(!issues.contains { [.answerUnit, .answerQuantityBound].contains($0.code) })
    }

    @Test("Evaluates core enableWhen and status-aware required rules", arguments: EnablementCase.allCases)
    func evaluatesCoreEnablement(testCase: EnablementCase) throws {
        var objects = try basePairObjects()
        var questionnaireGroup = try group(in: objects.questionnaire)
        let trigger = try question(in: objects.questionnaire)
        var target = trigger
        target["linkId"] = "target"
        target["text"] = "Target question"
        target["required"] = true
        target["enableWhen"] = [[
            "question": "question",
            "operator": testCase == .indeterminate ? ">" : "=",
            "answerBoolean": testCase == .disabledPresent ? false : true
        ]]
        questionnaireGroup["item"] = [trigger, target]
        try replaceGroup(in: &objects.questionnaire, with: questionnaireGroup)

        var responseGroup = try group(in: objects.response)
        let triggerResponse = try question(in: objects.response)
        var targetResponse = triggerResponse
        targetResponse["linkId"] = "target"
        targetResponse["text"] = "Target question"
        targetResponse["answer"] = [["valueBoolean": true]]
        responseGroup["item"] = testCase == .requiredMissing
            ? [triggerResponse]
            : [triggerResponse, targetResponse]
        try replaceGroup(in: &objects.response, with: responseGroup)

        let pair = try decodePair(objects)
        let issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        switch testCase {
        case .enabled:
            #expect(!issues.contains { [.itemDisabled, .requiredItem, .enableWhenEvaluation].contains($0.code) })
        case .disabledPresent:
            #expect(issues.contains { $0.code == .itemDisabled })
        case .requiredMissing:
            #expect(issues.contains { $0.code == .requiredItem })
        case .indeterminate:
            #expect(issues.contains { $0.code == .enableWhenEvaluation })
        }
    }

    @Test("Preserves unresolved warning target constraints", arguments: ConstraintLocation.allCases)
    func warningTargetConstraintIsReturnedWithoutRejectingPair(location: ConstraintLocation) throws {
        var objects = try basePairObjects()
        let constraint = targetConstraint(severity: "warning", key: "warn-\(location.rawValue)")
        switch location {
        case .root:
            appendExtension(constraint, to: &objects.questionnaire)
        case .item:
            var definition = try question(in: objects.questionnaire)
            appendExtension(constraint, to: &definition)
            try replaceQuestion(in: &objects.questionnaire, with: definition)
        }
        let resources = try decodePair(objects)
        let pair = try ResourcePair(
            questionnaire: resources.questionnaire,
            response: resources.response
        )
        #expect(pair.warnings.count == 1)
        #expect(pair.warnings.first?.severity == .warning)
        #expect(pair.warnings.first?.code == .expressionEngineRequired)
    }

    @Test("Blocks unresolved error target constraints", arguments: ConstraintLocation.allCases)
    func errorTargetConstraintBlocksPair(location: ConstraintLocation) throws {
        var objects = try basePairObjects()
        let constraint = targetConstraint(severity: "error", key: "error-\(location.rawValue)")
        switch location {
        case .root:
            appendExtension(constraint, to: &objects.questionnaire)
        case .item:
            var definition = try question(in: objects.questionnaire)
            appendExtension(constraint, to: &definition)
            try replaceQuestion(in: &objects.questionnaire, with: definition)
        }
        let pair = try decodePair(objects)
        #expect(throws: ContractError.self) {
            try ResourcePair(
                questionnaire: pair.questionnaire,
                response: pair.response
            )
        }
    }

    @Test("Rejects malformed expression contracts", arguments: ExpressionShapeCase.allCases)
    func rejectsMalformedExpressionShape(testCase: ExpressionShapeCase) throws {
        var objects = try basePairObjects()
        var definition = try question(in: objects.questionnaire)
        switch testCase {
        case .emptyExpression:
            appendExtension([
                "url": enableWhenExpression,
                "valueExpression": ["language": "text/fhirpath", "expression": "  "]
            ], to: &definition)
        case .incompleteTargetConstraint:
            appendExtension([
                "url": targetConstraintURL,
                "extension": [
                    ["url": "severity", "valueCode": "error"],
                    ["url": "expression", "valueExpression": [
                        "language": "text/fhirpath",
                        "expression": "true"
                    ]]
                ]
            ], to: &definition)
        case .mixedEnablementForms:
            definition["enableWhen"] = [[
                "question": "question",
                "operator": "exists",
                "answerBoolean": true
            ]]
            appendExtension([
                "url": enableWhenExpression,
                "valueExpression": ["language": "text/fhirpath", "expression": "true"]
            ], to: &definition)
        }
        try replaceQuestion(in: &objects.questionnaire, with: definition)
        let pair = try decodePair(objects)
        let issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(issues.contains { $0.code == .expressionShape })
    }

    @Test
    func enableWhenExpressionFailsClosedOnlyForCompletedOrAmendedResponses() throws {
        var objects = try basePairObjects()
        var definition = try question(in: objects.questionnaire)
        appendExtension([
            "url": enableWhenExpression,
            "valueExpression": ["language": "text/fhirpath", "expression": "true"]
        ], to: &definition)
        try replaceQuestion(in: &objects.questionnaire, with: definition)
        var pair = try decodePair(objects)
        var issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(issues.contains { $0.code == .expressionEngineRequired && $0.severity == .error })

        objects.response["status"] = "in-progress"
        pair = try decodePair(objects)
        issues = PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        )
        #expect(!issues.contains { $0.code == .expressionEngineRequired })
    }
}


extension GroveQuestionnaireFHIRPairRuleTests {
    private struct PairObjects {
        var questionnaire: JSONObject
        var response: JSONObject
    }

    private struct DecodedPair {
        let questionnaire: ModelsR4.Questionnaire
        let response: ModelsR4.QuestionnaireResponse
    }

    private static let canonical = URL(string: "https://example.org/fhir/Questionnaire/pair-rules")!
    private static let codingSystem = "https://example.org/fhir/CodeSystem/answers"
    private static let ucum = "http://unitsofmeasure.org"

    private var minLength: String { "http://hl7.org/fhir/StructureDefinition/minLength" }
    private var minValue: String { "http://hl7.org/fhir/StructureDefinition/minValue" }
    private var maxValue: String { "http://hl7.org/fhir/StructureDefinition/maxValue" }
    private var minQuantity: String {
        "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity"
    }
    private var maxQuantity: String {
        "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity"
    }
    private var maxDecimalPlaces: String { "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces" }
    private var unitOption: String { "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption" }
    private var unitValueSet: String { "http://hl7.org/fhir/StructureDefinition/questionnaire-unitValueSet" }
    private var mimeType: String { "http://hl7.org/fhir/StructureDefinition/mimeType" }
    private var maxSize: String { "http://hl7.org/fhir/StructureDefinition/maxSize" }
    private var minOccurs: String { "http://hl7.org/fhir/StructureDefinition/questionnaire-minOccurs" }
    private var maxOccurs: String { "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs" }
    private var optionExclusive: String {
        "http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive"
    }
    private var targetConstraintURL: String { "http://hl7.org/fhir/StructureDefinition/targetConstraint" }
    private var enableWhenExpression: String {
        "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression"
    }

    private func basePairObjects() throws -> PairObjects {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: Self.canonical,
            version: "1.0.0",
            title: "Pair Rules"
        ) {
            Section("section") {
                BooleanQuestion("question", "Question")
            }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["question"] = .init(value: .bool(true))
        let pair = try ResourceBuilder().pair(
            from: responses,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        return try PairObjects(
            questionnaire: object(pair.questionnaire),
            response: object(pair.response)
        )
    }

    private func object(_ resource: some Encodable) throws -> JSONObject {
        let data = try JSONEncoder().encode(resource)
        return try #require(JSONSerialization.jsonObject(with: data) as? JSONObject)
    }

    private func decodePair(_ objects: PairObjects) throws -> DecodedPair {
        let questionnaireData = try JSONSerialization.data(withJSONObject: objects.questionnaire)
        let responseData = try JSONSerialization.data(withJSONObject: objects.response)
        return try DecodedPair(
            questionnaire: JSONDecoder().decode(ModelsR4.Questionnaire.self, from: questionnaireData),
            response: JSONDecoder().decode(ModelsR4.QuestionnaireResponse.self, from: responseData)
        )
    }

    private func valueSet() throws -> ModelsR4.ValueSet {
        let object: JSONObject = [
            "resourceType": "ValueSet",
            "url": "https://example.org/fhir/ValueSet/answers",
            "version": "1.0.0",
            "status": "active",
            "compose": [
                "include": [[
                    "system": Self.codingSystem,
                    "concept": [["code": "allowed"]]
                ]]
            ]
        ]
        return try JSONDecoder().decode(
            ModelsR4.ValueSet.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func group(in object: JSONObject) throws -> JSONObject {
        try #require((object["item"] as? [JSONObject])?.first)
    }

    private func question(in object: JSONObject) throws -> JSONObject {
        let group = try group(in: object)
        return try #require((group["item"] as? [JSONObject])?.first)
    }

    private func replaceQuestion(in object: inout JSONObject, with question: JSONObject) throws {
        var group = try group(in: object)
        group["item"] = [question]
        object["item"] = [group]
    }

    private func replaceGroup(in object: inout JSONObject, with group: JSONObject) throws {
        object["item"] = [group]
    }

    private func appendExtension(_ newExtension: JSONObject, to object: inout JSONObject) {
        var extensions = object["extension"] as? [JSONObject] ?? []
        extensions.append(newExtension)
        object["extension"] = extensions
    }

    private func extensionJSON(_ url: String, _ valueKey: String, _ value: Any) -> JSONObject {
        ["url": url, valueKey: value]
    }

    private func coding(
        system: String = Self.codingSystem,
        code: String,
        version: String? = nil,
        display: String? = nil
    ) -> JSONObject {
        var coding: JSONObject = ["system": system, "code": code]
        coding["version"] = version
        coding["display"] = display
        return coding
    }

    private func quantity(value: Double, code: String, unit: String? = nil) -> JSONObject {
        var quantity: JSONObject = ["value": value, "system": Self.ucum, "code": code]
        quantity["unit"] = unit
        return quantity
    }

    private func targetConstraint(severity: String, key: String) -> JSONObject {
        [
            "url": targetConstraintURL,
            "extension": [
                ["url": "key", "valueId": key],
                ["url": "severity", "valueCode": severity],
                ["url": "human", "valueString": "Review this answer."],
                [
                    "url": "expression",
                    "valueExpression": ["language": "text/fhirpath", "expression": "true"]
                ]
            ]
        ]
    }
}
