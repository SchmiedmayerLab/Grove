//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing

// The scenarios spell out FHIR JSON and keep each case table next to its test, so that they stay comparable
// with the shared questionnaire scenarios.
// swiftlint:disable large_tuple multiline_literal_brackets type_contents_order


/// `enableWhen` as the pair validator evaluates it: which instance a condition reads, exact numeric
/// comparisons, `!=`, and coding identity.
@Suite
struct PairEnableWhenTests {
    private typealias JSONObject = [String: Any]

    private static let colors = "http://example.org/colors"
    fileprivate static let ucum = "http://unitsofmeasure.org"

    // MARK: Occurrences

    /// Three instances of a repeating group: a question before the gated item is read in the same instance, a
    /// question after it in the previous instance (in the first instance, the following one), a nested
    /// repeating group reads its enclosing instance, and items outside the group read the nearest instance.
    @Test
    func repeatingGroupInstancesFollowTheR4Axes() throws {
        let items: [JSONObject] = [
            display("preview", when: ["question": "score", "operator": ">", "answerInteger": 5]),
            [
                "linkId": "round", "type": "group", "repeats": true, "text": "Round",
                "item": [
                    ["linkId": "played", "type": "boolean", "text": "Played"],
                    question("score", "integer", when: ["question": "played", "operator": "=", "answerBoolean": true]),
                    display("bonus", when: ["question": "next", "operator": "=", "answerBoolean": true]),
                    ["linkId": "next", "type": "boolean", "text": "Another round"],
                    [
                        "linkId": "detail", "type": "group", "repeats": true, "text": "Detail",
                        "item": [
                            display("inner-note", when: ["question": "played", "operator": "=", "answerBoolean": true]),
                            display("inner-late", when: ["question": "late", "operator": "=", "answerBoolean": true])
                        ]
                    ],
                    ["linkId": "late", "type": "boolean", "text": "Late"]
                ]
            ],
            display("summary", when: ["question": "score", "operator": "exists", "answerBoolean": true])
        ]
        func round(played: Bool, score: Int?, next: Bool, late: Bool) -> JSONObject {
            var children: [JSONObject] = [answered("played", ["valueBoolean": played])]
            if let score {
                children.append(answered("score", ["valueInteger": score]))
            }
            children += [
                ["linkId": "bonus"],
                answered("next", ["valueBoolean": next]),
                ["linkId": "detail", "item": [["linkId": "inner-note"], ["linkId": "inner-late"]]],
                answered("late", ["valueBoolean": late])
            ]
            return ["linkId": "round", "item": children]
        }
        let issues = try issues(items: items, response: [
            ["linkId": "preview"],
            round(played: true, score: 8, next: false, late: true),
            round(played: true, score: 4, next: true, late: false),
            round(played: false, score: 9, next: true, late: true),
            ["linkId": "summary"]
        ])
        #expect(!issues.contains { $0.code == .itemDuplicate })
        #expect(disabled(issues) == [
            // `bonus` reads `next` of the first instance, in the first two instances.
            "QuestionnaireResponse.item[1].item[2]",
            "QuestionnaireResponse.item[2].item[2]",
            // The third instance was not played, so it has no score, and the second instance was not late.
            "QuestionnaireResponse.item[3].item[1]",
            "QuestionnaireResponse.item[3].item[4].item[0]",
            "QuestionnaireResponse.item[3].item[4].item[1]",
            // `summary` reads the score of the last instance, which is disabled and so counts as absent.
            "QuestionnaireResponse.item[4]"
        ])
    }

    /// Items nested under a question's answers read the whole question, every answer included.
    @Test
    func itemsUnderAnswersReadTheEnclosingQuestion() throws {
        let items: [JSONObject] = [
            [
                "linkId": "pain", "type": "boolean", "repeats": true, "text": "Pain",
                "item": [question("pain-site", "string", when: ["question": "pain", "operator": "=", "answerBoolean": true])]
            ],
            display("after-pain", when: ["question": "pain-site", "operator": "exists", "answerBoolean": true])
        ]
        let issues = try issues(items: items, response: [
            [
                "linkId": "pain",
                "answer": [
                    ["valueBoolean": true, "item": [answered("pain-site", ["valueString": "Knee"])]],
                    ["valueBoolean": false, "item": [answered("pain-site", ["valueString": "Ankle"])]]
                ]
            ],
            ["linkId": "after-pain"]
        ])
        #expect(disabled(issues).isEmpty)
    }

    /// A non-repeating group still reports a second instance.
    @Test
    func nonRepeatingGroupInstancesAreDuplicates() throws {
        let items: [JSONObject] = [
            ["linkId": "visit", "type": "group", "text": "Visit", "item": [["linkId": "attended", "type": "boolean", "text": "Attended"]]]
        ]
        let issues = try issues(items: items, response: [
            ["linkId": "visit", "item": [answered("attended", ["valueBoolean": true])]],
            ["linkId": "visit", "item": [answered("attended", ["valueBoolean": false])]]
        ])
        #expect(issues.contains { $0.code == .itemDuplicate })
    }

    // MARK: Numbers

    struct NumericCase: Sendable, CustomTestStringConvertible {
        let itemType: String
        let answer: JSONValue
        let condition: (key: String, value: JSONValue)
        let operation: String
        let holds: Bool

        var testDescription: String { "\(answer) \(operation) \(condition.key) \(condition.value) is \(holds)" }
    }

    /// A JSON value as a test argument.
    enum JSONValue: Sendable, CustomStringConvertible {
        case integer(Int)
        case decimal(Double)
        case string(String)
        case quantity(Double, code: String)

        var json: Any {
            switch self {
            case .integer(let value): value
            case .decimal(let value): value
            case .string(let value): value
            case let .quantity(value, code): ["value": value, "system": PairEnableWhenTests.ucum, "code": code]
            }
        }

        var description: String {
            switch self {
            case .integer(let value): "\(value)"
            case .decimal(let value): "\(value)"
            case .string(let value): value
            case let .quantity(value, code): "\(value) \(code)"
            }
        }
    }

    static let numericCases: [NumericCase] = {
        let decimalAgainstInteger: [(Double, String, Bool)] = [
            (80.5, ">=", true), (80.5, ">", true), (80.5, "=", false), (80.5, "!=", true), (80.5, "<", false), (80.5, "<=", false),
            (80.0, "=", true), (80.0, "!=", false), (80.0, ">=", true), (80.0, "<=", true), (80.0, ">", false), (80.0, "<", false),
            (79.9, "<", true), (79.9, "<=", true), (79.9, ">=", false), (79.9, "=", false)
        ]
        let integerAgainstDecimal: [(Int, Double, String, Bool)] = [
            (80, 80.0, "=", true), (80, 80.5, "<", true), (80, 80.5, "=", false), (80, 79.9, ">", true), (80, 80.0, "!=", false)
        ]
        let decimalAgainstDecimal: [(Double, Double, String, Bool)] = [
            (79.9, 79.9, "=", true), (36.52, 36.52, "=", true), (36.52, 36.5, ">", true), (0.1, 0.2, "<", true)
        ]
        return decimalAgainstInteger.map {
            NumericCase(itemType: "decimal", answer: .decimal($0.0), condition: ("answerInteger", .integer(80)), operation: $0.1, holds: $0.2)
        } + integerAgainstDecimal.map {
            NumericCase(itemType: "integer", answer: .integer($0.0), condition: ("answerDecimal", .decimal($0.1)), operation: $0.2, holds: $0.3)
        } + decimalAgainstDecimal.map {
            NumericCase(itemType: "decimal", answer: .decimal($0.0), condition: ("answerDecimal", .decimal($0.1)), operation: $0.2, holds: $0.3)
        }
    }()

    /// Integer and decimal values compare numerically and exactly, in either direction.
    @Test(arguments: numericCases)
    func numbersCompareExactly(testCase: NumericCase) throws {
        let answerKey = testCase.itemType == "integer" ? "valueInteger" : "valueDecimal"
        let items: [JSONObject] = [
            ["linkId": "weight", "type": testCase.itemType, "text": "Weight"],
            display("gated", when: ["question": "weight", "operator": testCase.operation, testCase.condition.key: testCase.condition.value.json])
        ]
        let issues = try issues(items: items, response: [answered("weight", [answerKey: testCase.answer.json]), ["linkId": "gated"]])
        #expect(disabled(issues).isEmpty == testCase.holds)
    }

    /// A decimal reads back with the digits it was written with, so `79.9` has one decimal place.
    @Test
    func decimalPlacesUseTheWrittenDigits() throws {
        let items: [JSONObject] = [[
            "linkId": "weight", "type": "decimal", "text": "Weight",
            "extension": [["url": "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces", "valueInteger": 1]]
        ]]
        let issues = try issues(items: items, response: [answered("weight", ["valueDecimal": 79.9])])
        #expect(!issues.contains { $0.code == .answerDecimalPlaces })
    }

    // MARK: Inequality and codings

    /// `!=` holds when no answer equals the value: without an answer, and when the question is disabled, whose
    /// answers count as absent.
    @Test
    func notEqualHoldsWhenNoAnswerIsEqual() throws {
        let items: [JSONObject] = [
            ["linkId": "smoker", "type": "boolean", "text": "Smoker"],
            question("packs", "integer", when: ["question": "smoker", "operator": "=", "answerBoolean": true]),
            display("not-smoker", when: ["question": "smoker", "operator": "!=", "answerBoolean": true]),
            display("not-one-pack", when: ["question": "packs", "operator": "!=", "answerInteger": 1])
        ]
        let unanswered = try issues(items: items, response: [["linkId": "not-smoker"], ["linkId": "not-one-pack"]])
        #expect(disabled(unanswered).isEmpty)
        let smokes = try issues(items: items, response: [
            answered("smoker", ["valueBoolean": true]),
            answered("packs", ["valueInteger": 1]),
            ["linkId": "not-smoker"],
            ["linkId": "not-one-pack"]
        ])
        #expect(disabled(smokes) == ["QuestionnaireResponse.item[2]", "QuestionnaireResponse.item[3]"])
        let doesNotSmoke = try issues(items: items, response: [
            answered("smoker", ["valueBoolean": false]),
            answered("packs", ["valueInteger": 1]),
            ["linkId": "not-smoker"],
            ["linkId": "not-one-pack"]
        ])
        #expect(disabled(doesNotSmoke) == ["QuestionnaireResponse.item[1]"])
    }

    /// An answer of a choice item with an `answerOption.value[x]` type other than Coding counts for enablement,
    /// besides being reported as an answer of the wrong type.
    @Test
    func choiceAnswersOfOptionValueTypesCount() throws {
        let items: [JSONObject] = [
            [
                "linkId": "level", "type": "choice", "text": "Level",
                "answerOption": [["valueInteger": 1], ["valueInteger": 3], ["valueInteger": 5]]
            ],
            display("three", when: ["question": "level", "operator": "=", "answerInteger": 3]),
            display("not-three", when: ["question": "level", "operator": "!=", "answerInteger": 3])
        ]
        let issues = try issues(items: items, response: [answered("level", ["valueInteger": 3]), ["linkId": "three"], ["linkId": "not-three"]])
        #expect(disabled(issues) == ["QuestionnaireResponse.item[2]"])
        #expect(issues.contains { $0.code == .answerType })
    }

    /// A condition on a calculated item reads the answer the response carries.
    @Test
    func calculatedAnswersAreRead() throws {
        let items: [JSONObject] = [
            [
                "linkId": "score", "type": "integer", "text": "Score", "readOnly": true,
                "extension": [[
                    "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                    "valueExpression": ["language": "text/fhirpath", "expression": "12"]
                ]]
            ],
            display("high", when: ["question": "score", "operator": ">", "answerInteger": 10]),
            display("low", when: ["question": "score", "operator": "<=", "answerInteger": 10])
        ]
        let result = try issues(items: items, response: [answered("score", ["valueInteger": 12]), ["linkId": "high"], ["linkId": "low"]])
        #expect(disabled(result) == ["QuestionnaireResponse.item[2]"])
    }

    /// An open choice's free-text answer carries the follow-up items without answers, and a later item reads them.
    @Test
    func freeTextAnswersHaveEmptyFollowUps() throws {
        let items: [JSONObject] = [
            [
                "linkId": "rounds", "type": "open-choice", "text": "Rounds", "repeats": true,
                "answerOption": [["valueCoding": ["system": "https://example.org/rounds", "code": "first"]]],
                "item": [["linkId": "played", "type": "boolean", "text": "Played"]]
            ],
            display("summary", when: ["question": "played", "operator": "=", "answerBoolean": true])
        ]
        let selected: JSONObject = [
            "valueCoding": ["system": "https://example.org/rounds", "code": "first"],
            "item": [answered("played", ["valueBoolean": true])]
        ]
        let withoutText = try issues(items: items, response: [["linkId": "rounds", "answer": [selected]], ["linkId": "summary"]])
        #expect(disabled(withoutText).isEmpty)
        let withText = try issues(items: items, response: [
            ["linkId": "rounds", "answer": [selected, ["valueString": "Other"]]],
            ["linkId": "summary"]
        ])
        #expect(disabled(withText) == ["QuestionnaireResponse.item[1]"])
    }

    // MARK: Conditions that cannot be evaluated

    /// A condition that names an unknown, shared or unanswerable item, compares an answer of another type, orders an
    /// unordered value, or sits among several conditions without `enableBehavior` cannot be evaluated; with `any` or
    /// `all`, the other conditions can still decide the outcome.
    @Test(arguments: [true, false])
    func conditionsThatCannotBeEvaluated(firstIsTrue: Bool) throws {
        let gates: [(String, [JSONObject], String?)] = [
            ("dangling", [["question": "missing", "operator": "=", "answerBoolean": true]], nil),
            ("group-target", [["question": "section", "operator": "exists", "answerBoolean": true]], nil),
            ("mismatch", [["question": "q1", "operator": "=", "answerInteger": 1]], nil),
            ("ordered-bool", [["question": "q1", "operator": ">", "answerBoolean": true]], nil),
            (
                "no-behavior",
                [["question": "q1", "operator": "=", "answerBoolean": true], ["question": "q1", "operator": "exists", "answerBoolean": true]],
                nil
            ),
            ("dup-ref", [["question": "dup", "operator": "exists", "answerBoolean": true]], nil),
            (
                "any-dangling",
                [["question": "q1", "operator": "=", "answerBoolean": true], ["question": "missing", "operator": "=", "answerBoolean": true]],
                "any"
            ),
            (
                "all-dangling",
                [["question": "q1", "operator": "=", "answerBoolean": true], ["question": "missing", "operator": "=", "answerBoolean": true]],
                "all"
            )
        ]
        var items: [JSONObject] = [
            ["linkId": "q1", "type": "boolean", "text": "First question"],
            ["linkId": "section", "type": "group", "text": "Section", "item": [["linkId": "dup", "type": "string", "text": "First use"]]],
            ["linkId": "dup", "type": "string", "text": "Second use"]
        ]
        for (linkId, conditions, behavior) in gates {
            var item: JSONObject = ["linkId": linkId, "type": "display", "text": linkId, "enableWhen": conditions]
            item["enableBehavior"] = behavior
            items.append(item)
        }
        let issues = try issues(
            items: items,
            response: [answered("q1", ["valueBoolean": firstIsTrue])] + gates.map { ["linkId": $0.0] },
            evaluable: false
        )
        let unevaluated = Set(gates.map(\.0).filter { gate in
            issues.contains { $0.code == .enableWhenEvaluation && $0.message.contains("'\(gate)'") }
        })
        #expect(unevaluated == Set(gates.map(\.0)).subtracting(firstIsTrue ? ["any-dangling"] : ["all-dangling"]))
        // With a false first answer, `all` fails on the condition that can be evaluated.
        #expect(disabled(issues) == (firstIsTrue ? [] : ["QuestionnaireResponse.item[8]"]))
    }

    /// An item whose enablement depends on itself cannot be evaluated; an item that reads it is decided when its
    /// outcome does not depend on whether that item is enabled.
    @Test(arguments: [false, true])
    func cyclesCannotBeEvaluated(answered aIsAnswered: Bool) throws {
        let items: [JSONObject] = [
            question("a", "boolean", when: ["question": "b", "operator": "exists", "answerBoolean": true]),
            question("b", "boolean", when: ["question": "a", "operator": "exists", "answerBoolean": true]),
            question("self", "boolean", when: ["question": "self", "operator": "=", "answerBoolean": true]),
            [
                "linkId": "outer", "type": "group", "text": "Outer",
                "enableWhen": [["question": "inner", "operator": "=", "answerBoolean": true]],
                "item": [["linkId": "inner", "type": "boolean", "text": "Inner"]]
            ],
            display("after-a", when: ["question": "a", "operator": "exists", "answerBoolean": true]),
            display("after-a-false", when: ["question": "a", "operator": "exists", "answerBoolean": false])
        ]
        let response: [JSONObject] = (aIsAnswered ? [answered("a", ["valueBoolean": true])] : [])
            + [["linkId": "after-a"], ["linkId": "after-a-false"]]
        let issues = try issues(items: items, response: response, evaluable: false)
        let unevaluated = Set(["a", "b", "self", "outer", "after-a", "after-a-false"].filter { linkId in
            issues.contains { $0.code == .enableWhenEvaluation && $0.message.contains("'\(linkId)'") }
        })
        #expect(unevaluated == (aIsAnswered ? ["a", "b", "self", "outer", "after-a", "after-a-false"] : ["a", "b", "self", "outer"]))
        // Without an answer, `a` has no answer whether or not it is enabled.
        #expect(disabled(issues) == (aIsAnswered ? [] : ["QuestionnaireResponse.item[0]"]))
    }

    // MARK: Typed values

    struct TypedCase: Sendable, CustomTestStringConvertible {
        let name: String
        let answers: [String: JSONValue]
        let disabled: Set<String>
        let notEvaluated: Set<String>

        var testDescription: String { name }
    }

    static let typedCases: [TypedCase] = [
        TypedCase(
            name: "typed values",
            answers: [
                "age": .integer(17), "weight": .decimal(70.5), "onset": .string("2019-12-31"),
                "visit": .string("2024-03-01T12:30:00+01:00"), "wake": .string("06:45:00"),
                "temperature": .quantity(38.5, code: "Cel")
            ],
            disabled: ["adult", "heavy", "heavy-integer"],
            notEvaluated: []
        ),
        TypedCase(
            name: "precision and units",
            answers: [
                "age": .integer(18), "weight": .integer(80), "onset": .string("2020-01"),
                "visit": .string("2024-03-01"), "wake": .string("07:30:00"),
                "temperature": .quantity(101, code: "[degF]")
            ],
            disabled: ["early-riser"],
            notEvaluated: ["early", "after-visit", "fever"]
        )
    ]

    /// Dates, date-times and times compare as points in time at the precision they state, and quantities in the
    /// unit of the threshold; values whose precision or unit leaves the order open cannot be evaluated.
    @Test(arguments: typedCases)
    func typedValuesCompareByTheirType(testCase: TypedCase) throws {
        let questions: [(String, String, String, String, Any)] = [
            ("age", "integer", "adult", ">=", ["answerInteger": 18]),
            ("weight", "decimal", "heavy", ">", ["answerDecimal": 70.5]),
            ("weight", "decimal", "heavy-integer", ">=", ["answerInteger": 80]),
            ("onset", "date", "early", "<", ["answerDate": "2020-01-01"]),
            ("visit", "dateTime", "after-visit", ">", ["answerDateTime": "2024-03-01T12:00:00+01:00"]),
            ("wake", "time", "early-riser", "<=", ["answerTime": "07:00:00"]),
            ("temperature", "quantity", "fever", ">=", ["answerQuantity": ["value": 38, "system": Self.ucum, "code": "Cel"]])
        ]
        var items: [JSONObject] = []
        var response: [JSONObject] = []
        for (linkId, type, gate, operation, answer) in questions {
            if !items.contains(where: { $0["linkId"] as? String == linkId }) {
                items.append(["linkId": linkId, "type": type, "text": linkId])
                let key = "value" + type.prefix(1).uppercased() + type.dropFirst()
                response.append(answered(linkId, [key: try #require(testCase.answers[linkId]).json]))
            }
            var condition = try #require(answer as? JSONObject)
            condition["question"] = linkId
            condition["operator"] = operation
            items.append(display(gate, when: condition))
            response.append(["linkId": gate])
        }
        let issues = try issues(items: items, response: response, evaluable: testCase.notEvaluated.isEmpty)
        let gates = response.enumerated().filter { entry in questions.contains { $0.2 == entry.element["linkId"] as? String } }
        #expect(disabled(issues) == Set(gates.filter { testCase.disabled.contains($0.element["linkId"] as? String ?? "") }.map {
            "QuestionnaireResponse.item[\($0.offset)]"
        }))
        let unevaluated = issues.filter { $0.code == .enableWhenEvaluation }.map(\.message)
        #expect(unevaluated.count == testCase.notEvaluated.count)
        for gate in testCase.notEvaluated {
            #expect(unevaluated.contains { $0.contains("'\(gate)'") }, "\(gate)")
        }
    }

    struct CodingCase: Sendable, CustomTestStringConvertible {
        let name: String
        let answers: [String?]
        /// The gated items that are disabled, by their condition.
        let disabled: Set<String>

        var testDescription: String { name }
    }

    static let codingCases: [CodingCase] = [
        CodingCase(name: "system red", answers: ["red"], disabled: ["without-system", "other-system"]),
        CodingCase(name: "red without a system", answers: [nil], disabled: ["with-system", "other-system", "not-red-without-system"]),
        CodingCase(name: "several, none blue", answers: ["red", nil], disabled: ["other-system", "not-red-without-system"]),
        CodingCase(name: "several, one blue", answers: ["red", "blue"], disabled: ["without-system", "other-system", "not-blue"]),
        CodingCase(name: "unanswered", answers: [], disabled: ["with-system", "without-system", "other-system"])
    ]

    /// A coding matches only when system and code are both equal; a coding without a system matches only an
    /// answer without a system. Every coding without a system is reported.
    @Test(arguments: codingCases)
    func codingsMatchOnSystemAndCode(testCase: CodingCase) throws {
        let gates: [(String, String, JSONObject)] = [
            ("with-system", "=", ["system": Self.colors, "code": "red"]),
            ("without-system", "=", ["code": "red"]),
            ("other-system", "=", ["system": "http://other.example/colors", "code": "red"]),
            ("not-blue", "!=", ["system": Self.colors, "code": "blue"]),
            ("not-red-without-system", "!=", ["code": "red"])
        ]
        let items: [JSONObject] = [[
            "linkId": "color", "type": "choice", "repeats": true, "text": "Colors",
            "answerOption": [
                ["valueCoding": ["system": Self.colors, "code": "red"]],
                ["valueCoding": ["system": Self.colors, "code": "blue"]],
                ["valueCoding": ["code": "red"]]
            ]
        ]] + gates.map { display($0.0, when: ["question": "color", "operator": $0.1, "answerCoding": $0.2]) }
        let answers: [JSONObject] = testCase.answers.map { code in
            ["valueCoding": code.map { ["system": Self.colors, "code": $0] } ?? ["code": "red"]]
        }
        var response: [JSONObject] = answers.isEmpty ? [] : [["linkId": "color", "answer": answers]]
        response += gates.map { ["linkId": $0.0] }
        let issues = try issues(items: items, response: response)
        let offset = response.count - gates.count
        #expect(disabled(issues) == Set(gates.enumerated().filter { testCase.disabled.contains($0.element.0) }.map {
            "QuestionnaireResponse.item[\($0.offset + offset)]"
        }))
        #expect(issues.filter { $0.code == .codingSystem }.map(\.path).sorted() == [
            "Questionnaire.item[0].answerOption[2].valueCoding",
            "Questionnaire.item[2].enableWhen[0].answerCoding",
            "Questionnaire.item[5].enableWhen[0].answerCoding"
        ])
        #expect(issues.filter { $0.code == .codingSystem }.allSatisfy { $0.severity == .warning })
    }
}


extension PairEnableWhenTests {
    private func display(_ linkId: String, when condition: JSONObject) -> JSONObject {
        ["linkId": linkId, "type": "display", "text": linkId, "enableWhen": [condition]]
    }

    private func question(_ linkId: String, _ type: String, when condition: JSONObject) -> JSONObject {
        ["linkId": linkId, "type": type, "text": linkId, "enableWhen": [condition]]
    }

    private func answered(_ linkId: String, _ answer: JSONObject) -> JSONObject {
        ["linkId": linkId, "answer": [answer]]
    }

    private func disabled(_ issues: [ValidationIssue]) -> Set<String> {
        Set(issues.filter { $0.code == .itemDisabled }.map(\.path))
    }

    /// The issues of a completed response with `response` items to a questionnaire with `items`.
    /// - parameter evaluable: Whether every enableWhen of the pair can be evaluated.
    private func issues(items: [JSONObject], response: [JSONObject], evaluable: Bool = true) throws -> [ValidationIssue] {
        let base = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/enable-when")),
            version: "1.0.0",
            language: "en-US",
            title: "Enable When"
        ) {
            Section("section") {
                BooleanQuestion("question", "Question")
            }
        }
        let responses = QuestionnaireResponses(questionnaire: base)
        responses.responses["question"] = .init(value: .bool(true))
        let pair = try ResourceBuilder().pair(
            from: responses,
            renderedIn: questionnaireResponseTestLocale,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        var questionnaire = try object(pair.questionnaire)
        var responseObject = try object(pair.response)
        questionnaire["item"] = items
        responseObject["item"] = response
        let decodedQuestionnaire = try JSONDecoder().decode(
            ModelsR4.Questionnaire.self,
            from: JSONSerialization.data(withJSONObject: questionnaire)
        )
        let decodedResponse = try JSONDecoder().decode(
            ModelsR4.QuestionnaireResponse.self,
            from: JSONSerialization.data(withJSONObject: responseObject)
        )
        let issues = PairValidator().issues(questionnaire: decodedQuestionnaire, response: decodedResponse)
        // Only the enablement outcome is under test.
        #expect(!issues.contains { [.itemUnknown, .itemMisplaced].contains($0.code) })
        if evaluable {
            #expect(!issues.contains { $0.code == .enableWhenEvaluation })
        }
        return issues
    }

    private func object(_ resource: some Encodable) throws -> JSONObject {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(resource)) as? JSONObject)
    }
}
