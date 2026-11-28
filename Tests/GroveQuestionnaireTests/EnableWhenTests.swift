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

// Each case table stays next to its test, so that it reads as the shared questionnaire scenarios do.
// swiftlint:disable large_tuple multiline_literal_brackets type_contents_order

/// `enableWhen` as the form evaluates it: exact numeric comparisons, `!=`, coding identity, and which
/// follow-up occurrence a condition reads.
@Suite
struct EnableWhenTests {
    private static let colors = "http://example.org/colors"

    // MARK: Numbers

    struct NumericCase: Sendable, CustomTestStringConvertible {
        let itemType: QuestionnaireItemType
        let response: Double
        let condition: Condition
        let operation: QuestionnaireItemOperator
        let holds: Bool

        enum Condition: Sendable {
            case integer(Int32)
            case decimal(String)
        }

        var testDescription: String { "\(response) \(operation.rawValue) \(condition) is \(holds)" }
    }

    static let numericCases: [NumericCase] = {
        let decimalAgainstInteger: [(Double, QuestionnaireItemOperator, Bool)] = [
            (80.5, .greaterThanOrEqual, true), (80.5, .greaterThan, true), (80.5, .equal, false),
            (80.5, .notEqual, true), (80.5, .lessThan, false), (80.5, .lessThanOrEqual, false),
            (80.0, .equal, true), (80.0, .notEqual, false), (80.0, .greaterThanOrEqual, true),
            (80.0, .lessThanOrEqual, true), (80.0, .greaterThan, false), (80.0, .lessThan, false),
            (79.9, .lessThan, true), (79.9, .lessThanOrEqual, true), (79.9, .greaterThanOrEqual, false), (79.9, .equal, false)
        ]
        let integerAgainstDecimal: [(Double, String, QuestionnaireItemOperator, Bool)] = [
            (80, "80.0", .equal, true), (80, "80.5", .lessThan, true), (80, "80.5", .equal, false),
            (80, "79.9", .greaterThan, true), (80, "80.0", .notEqual, false)
        ]
        let decimalAgainstDecimal: [(Double, String, QuestionnaireItemOperator, Bool)] = [
            (79.9, "79.9", .equal, true), (36.52, "36.52", .equal, true), (36.52, "36.5", .greaterThan, true),
            (80, "80.00000000000000001", .lessThan, true), (80, "80.00000000000000001", .equal, false)
        ]
        return decimalAgainstInteger.map {
            NumericCase(itemType: .decimal, response: $0.0, condition: .integer(80), operation: $0.1, holds: $0.2)
        } + integerAgainstDecimal.map {
            NumericCase(itemType: .integer, response: $0.0, condition: .decimal($0.1), operation: $0.2, holds: $0.3)
        } + decimalAgainstDecimal.map {
            NumericCase(itemType: .decimal, response: $0.0, condition: .decimal($0.1), operation: $0.2, holds: $0.3)
        }
    }()

    /// Integer and decimal values compare numerically and exactly, in either direction.
    @Test(arguments: numericCases)
    func numbersCompareExactly(testCase: NumericCase) throws {
        let answer: QuestionnaireItemEnableWhen.AnswerX = switch testCase.condition {
        case .integer(let value): .integer(FHIRPrimitive(FHIRInteger(value)))
        case .decimal(let value):
            .decimal(FHIRPrimitive(FHIRDecimal(try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))))))
        }
        let questionnaire = try questionnaire([
            item("weight", testCase.itemType),
            item("gated", .display, when: [condition("weight", testCase.operation, answer)])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(testCase.response))
        #expect(try enabled("gated", in: responses) == testCase.holds)
    }

    /// A decimal answer is exported with the digits the participant typed, so the pair rules see the same enablement as the form.
    @Test(arguments: ["36.52", "0.57", "79.9", "80.00000000000001"])
    func exportedDecimalsKeepTheirDigits(digits: String) throws {
        let value = try #require(Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")))
        let questionnaire = try questionnaire([
            item("weight", .decimal),
            item("note", .string, when: [condition("weight", .equal, .decimal(FHIRPrimitive(FHIRDecimal(value))))])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(try #require(Double(digits))))
        responses.responses["note"] = .init(value: .string("Shown"))
        #expect(try enabled("note", in: responses))
        let pair = try ResourceBuilder().pair(
            from: responses,
            renderedIn: questionnaireResponseTestLocale,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        let answer = pair.response.item?.first { $0.linkId.value?.string == "weight" }?.answer?.first?.value
        guard case .decimal(let exported)? = answer else {
            Issue.record("Expected a decimal answer")
            return
        }
        #expect(exported.value?.decimal == value)
        let issues = PairValidator().issues(questionnaire: pair.questionnaire, response: pair.response)
        #expect(!issues.contains { $0.code == .itemDisabled })
    }

    /// A quantity compares its magnitude exactly, in the unit the condition names.
    @Test
    func quantitiesCompareExactlyInTheirUnit() throws {
        func quantity(_ value: String, _ code: String) throws -> QuestionnaireItemEnableWhen.AnswerX {
            .quantity(Quantity(
                code: code.asFHIRStringPrimitive(),
                system: "http://unitsofmeasure.org",
                value: FHIRPrimitive(FHIRDecimal(try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))))
            ))
        }
        var weight = item("weight", .quantity)
        weight.extension = [Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unit",
            value: .coding(Coding(code: "kg", system: "http://unitsofmeasure.org"))
        )]
        let questionnaire = try questionnaire([
            weight,
            item("at-least", .display, when: [condition("weight", .greaterThanOrEqual, try quantity("80", "kg"))]),
            item("other-unit", .display, when: [condition("weight", .greaterThanOrEqual, try quantity("80", "[lb_av]"))]),
            item("without-unit", .display, when: [
                condition("weight", .greaterThanOrEqual, .quantity(Quantity(value: FHIRPrimitive(FHIRDecimal(Decimal(80))))))
            ])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(80.5))
        #expect(try enabled("at-least", in: responses))
        #expect(try !enabled("other-unit", in: responses))
        // A quantity without a unit orders only answers without a unit.
        #expect(try !enabled("without-unit", in: responses))
    }

    /// Dates compare as far as both state them; a partial date that agrees with a full one has no order,
    /// so neither `=` nor `!=` is met.
    @Test
    func partialDatesCompareAtTheirPrecision() throws {
        func date(_ text: String) throws -> QuestionnaireItemEnableWhen.AnswerX {
            .date(FHIRPrimitive(try FHIRDate(text)))
        }
        let questionnaire = try questionnaire([
            item("visit", .date),
            item("in-2024", .display, when: [condition("visit", .equal, try date("2024"))]),
            item("after-2023", .display, when: [condition("visit", .greaterThan, try date("2023"))]),
            item("before-2024-04", .display, when: [condition("visit", .lessThan, try date("2024-04"))]),
            item("not-2024", .display, when: [condition("visit", .notEqual, try date("2024"))]),
            item("seen", .dateTime),
            item("seen-after-2024", .display, when: [condition("seen", .greaterThan, .dateTime(FHIRPrimitive(DateTime("2024"))))]),
            item("seen-after-2023", .display, when: [condition("seen", .greaterThan, .dateTime(FHIRPrimitive(DateTime("2023"))))]),
            // A date-time answer on the day of a date without a time has no order relative to it.
            item("seen-on-the-day", .display, when: [condition("seen", .greaterThanOrEqual, .dateTime(FHIRPrimitive(DateTime("2024-03-05"))))]),
            item("seen-not-on-the-day", .display, when: [condition("seen", .notEqual, .dateTime(FHIRPrimitive(DateTime("2024-03-05"))))]),
            item("seen-after-the-day-before", .display, when: [
                condition("seen", .greaterThan, .dateTime(FHIRPrimitive(DateTime("2024-03-04"))))
            ])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["visit"] = .init(value: .date(DateComponents(year: 2024, month: 3, day: 5)))
        #expect(try !enabled("in-2024", in: responses))
        #expect(try enabled("after-2023", in: responses))
        #expect(try enabled("before-2024-04", in: responses))
        #expect(try !enabled("not-2024", in: responses))
        responses.responses["seen"] = .init(value: .date(DateComponents(year: 2024, month: 3, day: 5, hour: 10, minute: 0)))
        #expect(try !enabled("seen-after-2024", in: responses))
        #expect(try enabled("seen-after-2023", in: responses))
        #expect(try !enabled("seen-on-the-day", in: responses))
        #expect(try !enabled("seen-not-on-the-day", in: responses))
        #expect(try enabled("seen-after-the-day-before", in: responses))
    }

    /// Integer answer options compare numerically, with every operator.
    @Test
    func integerOptionsCompareNumerically() throws {
        var score = item("score", .choice)
        score.repeats = true
        score.answerOption = [1, 3, 5].map { QuestionnaireItemAnswerOption(value: .integer(FHIRPrimitive(FHIRInteger($0)))) }
        let questionnaire = try questionnaire([
            score,
            item("above-four", .display, when: [condition("score", .greaterThan, .integer(4))]),
            item("three", .display, when: [condition("score", .equal, .integer(3))]),
            // An integer option has integer values; a decimal condition on it is not met, as the pair rules cannot evaluate it.
            item("three-as-decimal", .display, when: [condition("score", .equal, .decimal(FHIRPrimitive(FHIRDecimal(3))))]),
            item("below-one", .display, when: [condition("score", .lessThan, .integer(1))])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["score"] = .init(value: .choice(.init(selectedOptions: ["integer|3", "integer|5"])))
        #expect(try enabled("above-four", in: responses))
        #expect(try enabled("three", in: responses))
        #expect(try !enabled("three-as-decimal", in: responses))
        #expect(try !enabled("below-one", in: responses))
    }

    /// A decimal initial value keeps its digits, so it equals the same decimal in a condition.
    @Test
    func decimalInitialValueEqualsTheSameDecimal() throws {
        let value = FHIRPrimitive(FHIRDecimal(try #require(Decimal(string: "36.52", locale: Locale(identifier: "en_US_POSIX")))))
        var temperature = item("temperature", .decimal)
        temperature.initial = [QuestionnaireItemInitial(value: .decimal(value))]
        let questionnaire = try questionnaire([
            temperature,
            item("gated", .display, when: [condition("temperature", .equal, .decimal(value))])
        ])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.responses["temperature"].value.numberValue == 36.52)
        #expect(try enabled("gated", in: responses))
    }

    // MARK: Inequality and codings

    /// `!=` holds when no answer equals the value, so also without an answer; with several answers, one equal
    /// answer is enough to make it fail.
    @Test
    func notEqualHoldsWhenNoAnswerIsEqual() throws {
        let questionnaire = try codingQuestionnaire()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(try enabled("not-blue", in: responses))
        responses.responses["color"] = .init(value: .choice(.init(selectedOptions: ["\(Self.colors)|red"])))
        #expect(try enabled("not-blue", in: responses))
        responses.responses["color"] = .init(value: .choice(.init(selectedOptions: ["\(Self.colors)|red", "\(Self.colors)|blue"])))
        #expect(try !enabled("not-blue", in: responses))
    }

    struct CodingCase: Sendable, CustomTestStringConvertible {
        let name: String
        let selected: Set<String>
        let enabled: Set<String>

        var testDescription: String { name }
    }

    static let codingCases: [CodingCase] = [
        CodingCase(name: "system red", selected: ["\(colors)|red"], enabled: ["with-system", "not-blue", "not-red-without-system"]),
        CodingCase(name: "red without a system", selected: ["red"], enabled: ["without-system", "not-blue"]),
        CodingCase(name: "several, none blue", selected: ["\(colors)|red", "red"], enabled: ["with-system", "without-system", "not-blue"]),
        CodingCase(
            name: "several, one blue",
            selected: ["\(colors)|red", "\(colors)|blue"],
            enabled: ["with-system", "not-red-without-system"]
        ),
        CodingCase(name: "unanswered", selected: [], enabled: ["not-blue", "not-red-without-system"])
    ]

    /// A coding matches only when system and code are both equal; a coding without a system matches only an
    /// answer without a system.
    @Test(arguments: codingCases)
    func codingsMatchOnSystemAndCode(testCase: CodingCase) throws {
        let questionnaire = try codingQuestionnaire()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["color"] = .init(value: .choice(.init(selectedOptions: testCase.selected)))
        for gate in ["with-system", "without-system", "other-system", "not-blue", "not-red-without-system"] {
            #expect(try enabled(gate, in: responses) == testCase.enabled.contains(gate), "\(gate)")
        }
    }

    /// Every enableWhen coding and answer option without a system is reported.
    @Test
    func codingsWithoutSystemAreReported() throws {
        let warnings = try codingQuestionnaire().metadata.administrationWarnings
        #expect(warnings.filter { $0.contains("has no system") }.count == 3)
        #expect(warnings.contains { $0.contains("answer option 'red' on item 'color'") })
        #expect(warnings.contains { $0.contains("enableWhen coding 'red' on item 'without-system'") })
        #expect(warnings.contains { $0.contains("enableWhen coding 'red' on item 'not-red-without-system'") })
    }

    // MARK: Follow-up occurrences

    /// A follow-up task occurs once for every selected option. A question before the gated follow-up is read in
    /// the same occurrence, a question after it in the previous one (in the first, the following one), and a
    /// task outside reads the nearest occurrence before it, or else the first after it.
    @Test
    func followUpOccurrencesFollowTheR4Axes() throws { // swiftlint:disable:this function_body_length
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "preview", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    )),
                    .init(id: "rounds", title: "", kind: .choice(.init(
                        options: [.init(id: "first", title: "First"), .init(id: "second", title: "Second"), .init(id: "third", title: "Third")],
                        allowsMultipleSelection: true,
                        followUpTasks: [
                            .init(id: "played", title: "", kind: .boolean),
                            .init(id: "bonus", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                taskId: "next", operator: .equal, value: .bool(true)
                            )),
                            .init(id: "next", title: "", kind: .boolean),
                            .init(id: "score", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                taskId: "played", operator: .equal, value: .bool(true)
                            )),
                            .init(id: "picked", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                taskId: "rounds", operator: .equal, value: .SCMCOption(id: "third")
                            ))
                        ]
                    ))),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        // The options are selected out of order; occurrences follow the order of the options.
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["third", "first", "second"])))
        let answers: [(String, played: Bool, next: Bool)] = [("first", true, false), ("second", true, true), ("third", false, true)]
        func round(_ option: String) -> QuestionnaireResponses {
            responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: option))
        }
        for (option, played, next) in answers {
            round(option).responses["played"] = .init(value: .bool(played))
            round(option).responses["next"] = .init(value: .bool(next))
        }
        let rounds = try #require(questionnaire.task(withId: "rounds"))
        let followUp = { (id: String) in try #require(rounds.kind.followUpTasks.first { $0.id == id }) }
        // `bonus` reads `next` of the first occurrence in the first two rounds, and of the second in the third.
        #expect(try !round("first").shouldEnable(task: followUp("bonus")))
        #expect(try !round("second").shouldEnable(task: followUp("bonus")))
        #expect(try round("third").shouldEnable(task: followUp("bonus")))
        // `score` reads `played` of its own round.
        #expect(try round("first").shouldEnable(task: followUp("score")))
        #expect(try !round("third").shouldEnable(task: followUp("score")))
        // `picked` reads its enclosing choice task, with every selected option.
        #expect(try round("first").shouldEnable(task: followUp("picked")))
        // `preview` reads the first round; `summary` reads the last.
        #expect(try enabled("preview", in: responses))
        #expect(try !enabled("summary", in: responses))
        // Without the third round, the second round is the last.
        responses.responses["rounds"].value = .choice(.init(selectedOptions: ["first", "second"]))
        #expect(try enabled("summary", in: responses))
    }

    /// A follow-up nested two levels deep reads the nearest preceding occurrence, which is in its own visit.
    @Test
    func nestedFollowUpsReadTheNearestPrecedingOccurrence() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "visits", title: "", kind: .choice(.init(
                        options: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
                        allowsMultipleSelection: true,
                        followUpTasks: [
                            .init(id: "attended", title: "", kind: .boolean),
                            .init(id: "topics", title: "", kind: .choice(.init(
                                options: [.init(id: "x", title: "X")],
                                allowsMultipleSelection: false,
                                followUpTasks: [
                                    .init(id: "note", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                        taskId: "attended", operator: .equal, value: .bool(true)
                                    ))
                                ]
                            )))
                        ]
                    )))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["visits"] = .init(value: .choice(.init(selectedOptions: ["a", "b"])))
        func visit(_ option: String) -> QuestionnaireResponses {
            responses.view(appending: .init().appending(taskId: "visits").appending(choiceOption: option))
        }
        visit("a").responses["attended"] = .init(value: .bool(true))
        visit("b").responses["attended"] = .init(value: .bool(false))
        for option in ["a", "b"] {
            visit(option).responses["topics"] = .init(value: .choice(.init(selectedOptions: ["x"])))
        }
        let note = try #require(questionnaire.task(at: ["visits", "topics", "note"]))
        func topic(_ option: String) -> QuestionnaireResponses {
            visit(option).view(appending: .init().appending(taskId: "topics").appending(choiceOption: "x"))
        }
        #expect(topic("a").shouldEnable(task: note))
        #expect(!topic("b").shouldEnable(task: note))
    }

    /// The follow-up tasks of a disabled choice task occur without answers, so a task outside cannot read their answers.
    @Test
    func followUpsOfADisabledChoiceTaskHaveNoAnswers() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "asked", title: "", kind: .boolean),
                    .init(
                        id: "rounds",
                        title: "",
                        kind: .choice(.init(
                            options: [.init(id: "first", title: "First")],
                            allowsMultipleSelection: true,
                            followUpTasks: [.init(id: "played", title: "", kind: .boolean)]
                        )),
                        enabledCondition: .responseValueComparison(taskId: "asked", operator: .equal, value: .bool(true))
                    ),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["asked"] = .init(value: .bool(true))
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["played"] = .init(value: .bool(true))
        #expect(try enabled("summary", in: responses))
        responses.responses["asked"].value = .bool(false)
        #expect(try !enabled("summary", in: responses))
    }

    /// The follow-up tasks of a custom question kind occur in the containers the kind stores responses in.
    @Test
    func customKindFollowUpsResolve() throws {
        struct Config: QuestionKindConfig {
            let followUpTasks: [GroveQuestionnaire.Questionnaire.Task]
        }
        struct FollowUpKind: QuestionKindDefinition {
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }
        }
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "custom", title: "", kind: .custom(FollowUpKind.self, config: Config(followUpTasks: [
                        .init(id: "played", title: "", kind: .boolean),
                        .init(id: "bonus", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                            taskId: "played", operator: .equal, value: .bool(true)
                        ))
                    ]))),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        // Follow-up responses are kept only under a task that has a response.
        responses.responses["custom"] = .init(value: .string("entry"))
        let nested = responses.view(appending: .init().appending(taskId: "custom").appending(choiceOption: "entry"))
        nested.responses["played"] = .init(value: .bool(true))
        let bonus = try #require(questionnaire.task(at: ["custom", "bonus"]))
        #expect(nested.shouldEnable(task: bonus))
        #expect(try enabled("summary", in: responses))
        nested.responses["played"].value = .bool(false)
        #expect(!nested.shouldEnable(task: bonus))
        #expect(try !enabled("summary", in: responses))
    }

    /// A free-text answer of an open choice is the last answer, and the follow-up tasks occur beneath it without
    /// answers, as in the exported response; a task after the choice reads that occurrence.
    @Test
    func freeTextAnswerHasEmptyFollowUps() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "rounds", title: "", kind: .choice(.init(
                        options: [.init(id: "first", title: "First")],
                        hasFreeTextOtherOption: true,
                        allowsMultipleSelection: true,
                        followUpTasks: [.init(id: "played", title: "", kind: .boolean)]
                    ))),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["played"] = .init(value: .bool(true))
        #expect(try enabled("summary", in: responses))
        responses.responses["rounds"].value = .choice(.init(selectedOptions: ["first"], freeTextOtherResponse: "Other"))
        #expect(try !enabled("summary", in: responses))
    }

    /// A follow-up task of a custom kind reads its conditions also in a container that holds no responses yet.
    @Test
    func customKindFollowUpsResolveInAnEmptyContainer() throws {
        struct Config: QuestionKindConfig {
            let followUpTasks: [GroveQuestionnaire.Questionnaire.Task]
        }
        struct FollowUpKind: QuestionKindDefinition {
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }
        }
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "consent", title: "", kind: .boolean),
                    .init(id: "custom", title: "", kind: .custom(FollowUpKind.self, config: Config(followUpTasks: [
                        .init(id: "bonus", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                            taskId: "consent", operator: .equal, value: .bool(true)
                        ))
                    ])))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["consent"] = .init(value: .bool(true))
        responses.responses["custom"] = .init(value: .string("entry"))
        let nested = responses.view(appending: .init().appending(taskId: "custom").appending(choiceOption: "entry"))
        let bonus = try #require(questionnaire.task(at: ["custom", "bonus"]))
        #expect(nested.shouldEnable(task: bonus))
    }

    /// A custom kind's container without stored responses is an occurrence of its own, so a follow-up there reads
    /// its own unanswered sibling and not the answer in another container.
    @Test
    func customKindEmptyContainerReadsItsOwnFollowUps() throws {
        struct Config: QuestionKindConfig {
            let followUpTasks: [GroveQuestionnaire.Questionnaire.Task]
        }
        struct FollowUpKind: QuestionKindDefinition {
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }
        }
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "custom", title: "", kind: .custom(FollowUpKind.self, config: Config(followUpTasks: [
                        .init(id: "played", title: "", kind: .boolean),
                        .init(id: "bonus", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                            taskId: "played", operator: .equal, value: .bool(true)
                        ))
                    ])))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["custom"] = .init(value: .string("entries"))
        responses.view(appending: .init().appending(taskId: "custom").appending(choiceOption: "a"))
            .responses["played"] = .init(value: .bool(true))
        let empty = responses.view(appending: .init().appending(taskId: "custom").appending(choiceOption: "b"))
        let bonus = try #require(questionnaire.task(at: ["custom", "bonus"]))
        #expect(!empty.shouldEnable(task: bonus))
    }

    /// A condition that cannot be evaluated satisfies no operator, `!=` included, as the pair rules report it;
    /// `any` and `all` still decide where the other conditions suffice.
    @Test
    func conditionsThatCannotBeEvaluatedSatisfyNoOperator() throws {
        func task(_ id: String, _ condition: GroveQuestionnaire.Questionnaire.Condition) -> GroveQuestionnaire.Questionnaire.Task {
            .init(id: id, title: "", kind: .boolean, enabledCondition: condition)
        }
        let flagIsTrue = GroveQuestionnaire.Questionnaire.Condition.responseValueComparison(taskId: "flag", operator: .equal, value: .bool(true))
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "flag", title: "", kind: .boolean),
                    task("other-type", .responseValueComparison(taskId: "flag", operator: .notEqual, value: .string("x"))),
                    task("itself", .responseValueComparison(taskId: "itself", operator: .notEqual, value: .bool(true))),
                    task("unknown", .responseValueComparison(taskId: "missing", operator: .notEqual, value: .bool(true))),
                    task("not-unknown", .not(.hasResponse(taskId: "missing"))),
                    task("any-decides", .any([.hasResponse(taskId: "missing"), flagIsTrue])),
                    task("all-decides", .all([.hasResponse(taskId: "missing"), .not(flagIsTrue)])),
                    task("cycle-a", .responseValueComparison(taskId: "cycle-b", operator: .notEqual, value: .bool(true))),
                    task("cycle-b", .responseValueComparison(taskId: "cycle-a", operator: .notEqual, value: .bool(true))),
                    // An ordered operator on a value without an order, and an open comparison, stay open under `not`.
                    task("not-ordered-boolean", .not(.responseValueComparison(taskId: "flag", operator: .greaterThan, value: .bool(true)))),
                    .init(id: "visit", title: "", kind: .dateTime(.init(style: .dateOnly))),
                    task("not-in-2024", .not(.responseValueComparison(taskId: "visit", operator: .equal, value: .date(DateComponents(year: 2024))))),
                    // A cycle through the condition of a choice task whose follow-up task is referenced.
                    task("outer", .responseValueComparison(taskId: "inner", operator: .notEqual, value: .bool(true))),
                    .init(
                        id: "rounds",
                        title: "",
                        kind: .choice(.init(
                            options: [.init(id: "first", title: "First")],
                            allowsMultipleSelection: false,
                            followUpTasks: [.init(id: "inner", title: "", kind: .boolean)]
                        )),
                        enabledCondition: .responseValueComparison(taskId: "outer", operator: .equal, value: .bool(true))
                    )
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["flag"] = .init(value: .bool(true))
        responses.responses["visit"] = .init(value: .date(DateComponents(year: 2024, month: 3, day: 5)))
        responses.responses["outer"] = .init(value: .bool(true))
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["inner"] = .init(value: .bool(true))
        let ids = ["other-type", "itself", "unknown", "not-unknown", "all-decides", "cycle-a", "cycle-b", "not-ordered-boolean", "not-in-2024", "outer"]
        for id in ids {
            #expect(try !enabled(id, in: responses), "\(id)")
        }
        #expect(try enabled("any-decides", in: responses))
    }

    /// The comparison operators of a quantity question compare in the question's unit.
    @Test
    func quantityQuestionOperatorsCompareInTheirUnit() throws {
        let weight = NumberQuestion.quantity("weight", "Weight", unit: "kg")
        let condition = weight >= 80
        #expect(condition == .responseValueComparison(taskId: "weight", operator: .greaterThanOrEqual, value: .quantity(value: 80, system: URL(string: "http://unitsofmeasure.org"), code: "kg", unit: "kg")))
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: weight._makeTasks() + [
                    .init(id: "heavy", title: "", kind: .boolean, enabledCondition: weight >= 80),
                    .init(id: "not-light", title: "", kind: .boolean, enabledCondition: !(weight < 80))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(85))
        #expect(try enabled("heavy", in: responses))
        #expect(try enabled("not-light", in: responses))
    }

    /// A choice task without a selection, or a disabled one, holds its follow-up tasks once without answers, so a
    /// condition reads that occurrence instead of reaching an answer in another container, as the pair rules do.
    @Test
    func nestedFollowUpsOfAnUnansweredChoiceHaveNoAnswers() throws {
        let inner = GroveQuestionnaire.Questionnaire.Task(
            id: "inner",
            title: "",
            kind: .choice(.init(
                options: [.init(id: "o", title: "O")],
                allowsMultipleSelection: false,
                followUpTasks: [.init(id: "detail", title: "", kind: .boolean)]
            )),
            enabledCondition: .responseValueComparison(taskId: "asked", operator: .equal, value: .bool(true))
        )
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "visits", title: "", kind: .choice(.init(
                        options: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
                        allowsMultipleSelection: true,
                        followUpTasks: [
                            .init(id: "asked", title: "", kind: .boolean),
                            inner,
                            .init(id: "noted", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                taskId: "detail", operator: .equal, value: .bool(true)
                            ))
                        ]
                    ))),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "detail", operator: .equal, value: .bool(true)
                    )),
                    .init(id: "no-summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "detail", operator: .notEqual, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        func visit(_ option: String) -> QuestionnaireResponses {
            responses.view(appending: .init().appending(taskId: "visits").appending(choiceOption: option))
        }
        responses.responses["visits"] = .init(value: .choice(.init(selectedOptions: ["a", "b"])))
        visit("a").responses["asked"] = .init(value: .bool(true))
        visit("a").responses["inner"] = .init(value: .choice(.init(selectedOptions: ["o"])))
        visit("a").view(appending: .init().appending(taskId: "inner").appending(choiceOption: "o"))
            .responses["detail"] = .init(value: .bool(true))
        let noted = try #require(questionnaire.task(at: ["visits", "noted"]))
        // Visit b asks the inner question but has no answer to it yet.
        visit("b").responses["asked"] = .init(value: .bool(true))
        #expect(visit("a").shouldEnable(task: noted))
        #expect(!visit("b").shouldEnable(task: noted))
        #expect(try !enabled("summary", in: responses))
        #expect(try enabled("no-summary", in: responses))
        // In visit b the inner question is disabled.
        visit("b").responses["asked"] = .init(value: .bool(false))
        #expect(!visit("b").shouldEnable(task: noted))
        #expect(try !enabled("summary", in: responses))
        #expect(try enabled("no-summary", in: responses))
    }

    /// A part that cannot be evaluated does not settle `all` or `any`, also under `not`.
    @Test
    func openPartsDoNotSettleTheirCondition() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "flag", title: "", kind: .boolean),
                    .init(id: "gated", title: "", kind: .boolean, enabledCondition: .not(.all([
                        .hasResponse(taskId: "missing"),
                        .responseValueComparison(taskId: "flag", operator: .notEqual, value: .bool(true))
                    ])))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let gated = try #require(questionnaire.task(withId: "gated"))
        #expect(!responses.isEnablementSettled(for: gated))
        responses.responses["flag"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: gated))
    }

    /// A condition on a follow-up task that has no occurrence yet stays unsettled, since an option selected later
    /// can still make it occur.
    @Test
    func conditionOnAFollowUpWithoutOccurrenceIsUnsettled() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "rounds", title: "", kind: .choice(.init(
                        options: [.init(id: "first", title: "First")],
                        allowsMultipleSelection: true,
                        followUpTasks: [
                            .init(id: "played", title: "", kind: .boolean),
                            .init(id: "scored", title: "", kind: .boolean, enabledCondition: .hasResponse(taskId: "played"))
                        ]
                    ))),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    )),
                    // A follow-up target with a condition of its own is unsettled in the same way.
                    .init(id: "conditioned-summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "scored", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let summary = try #require(questionnaire.task(withId: "summary"))
        let conditioned = try #require(questionnaire.task(withId: "conditioned-summary"))
        #expect(!responses.isEnablementSettled(for: summary))
        #expect(!responses.isEnablementSettled(for: conditioned))
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["played"] = .init(value: .bool(true))
        #expect(responses.isEnablementSettled(for: summary))
    }

    /// A chain of about a hundred conditional choice tasks evaluates on a thread with a small stack, since the
    /// enablement of the tasks a condition depends on is not evaluated by recursion.
    @Test(.timeLimit(.minutes(1)))
    func longConditionChainsDoNotDependOnTheThreadStack() async throws {
        let length = 100
        let tasks: [GroveQuestionnaire.Questionnaire.Task] = (0..<length).map { index in
            .init(
                id: "choice\(index)",
                title: "",
                kind: .choice(.init(
                    options: [.init(id: "yes", title: "Yes")],
                    allowsMultipleSelection: false,
                    followUpTasks: [.init(id: "detail\(index)", title: "", kind: .boolean)]
                )),
                enabledCondition: index == 0 ? .none : .responseValueComparison(
                    taskId: "detail\(index - 1)", operator: .notEqual, value: .bool(false)
                )
            )
        }
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [.init(id: "section", tasks: tasks + [
                .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                    taskId: "detail\(length - 1)", operator: .equal, value: .bool(true)
                ))
            ])]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        for index in 0..<length {
            responses.responses["choice\(index)"] = .init(value: .choice(.init(selectedOptions: ["yes"])))
            responses.view(appending: .init().appending(taskId: "choice\(index)").appending(choiceOption: "yes"))
                .responses["detail\(index)"] = .init(value: .bool(true))
        }
        let summary = try #require(questionnaire.task(withId: "summary"))
        // The responses are used only on the thread until it resumes the continuation.
        nonisolated(unsafe) let evaluated = responses
        let outcome = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: [evaluated.shouldEnable(task: summary), evaluated.isEnablementSettled(for: summary)])
            }
            thread.stackSize = 128 * 1024
            thread.start()
        }
        #expect(outcome == [true, true])
    }

    /// A follow-up task of a choice task that is disabled for good is settled: no answer still to be given lets
    /// it occur, so a condition on it no longer counts towards the questions that may be asked.
    @Test
    func followUpsOfAPermanentlyDisabledChoiceAreSettled() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "plays", title: "", kind: .boolean),
                    .init(
                        id: "rounds",
                        title: "",
                        kind: .choice(.init(
                            options: [.init(id: "first", title: "First")],
                            allowsMultipleSelection: false,
                            followUpTasks: [.init(id: "played", title: "", kind: .boolean)]
                        )),
                        enabledCondition: .responseValueComparison(taskId: "plays", operator: .equal, value: .bool(true))
                    ),
                    .init(id: "summary", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "played", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let summary = try #require(questionnaire.task(withId: "summary"))
        // While `plays` is unanswered, `rounds` and with it `played` can still be asked.
        #expect(!responses.isEnablementSettled(for: summary))
        // A selection and an answer stored beneath `rounds` do not count while it is disabled, and leave the
        // condition open while `rounds` can still be enabled.
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["played"] = .init(value: .bool(true))
        #expect(!responses.shouldEnable(task: summary))
        #expect(!responses.isEnablementSettled(for: summary))
        responses.responses["plays"] = .init(value: .bool(false))
        #expect(!responses.shouldEnable(task: summary))
        #expect(responses.isEnablementSettled(for: summary))
        responses.responses["rounds"] = .init(value: .none)
        #expect(responses.isEnablementSettled(for: summary))
        responses.responses["rounds"] = .init(value: .choice(.init(selectedOptions: ["first"])))
        responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
            .responses["played"] = .init(value: .bool(true))
        responses.responses["plays"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: summary))
    }

    /// In the container of an unselected option, where a follow-up task's condition can still be evaluated, a
    /// condition on another follow-up task reads its occurrence without answers.
    @Test
    func conditionsInAnUnselectedOptionReadTheOccurrenceWithoutAnswers() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "rounds", title: "", kind: .choice(.init(
                        options: [.init(id: "first", title: "First")],
                        allowsMultipleSelection: false,
                        followUpTasks: [
                            .init(id: "played", title: "", kind: .boolean),
                            .init(id: "bonus", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                                taskId: "played", operator: .notEqual, value: .bool(true)
                            )),
                            .init(id: "extra", title: "", kind: .boolean, enabledCondition: .not(.hasResponse(taskId: "played")))
                        ]
                    )))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let first = responses.view(appending: .init().appending(taskId: "rounds").appending(choiceOption: "first"))
        let followUps = try #require(questionnaire.task(withId: "rounds")).kind.followUpTasks
        let bonus = try #require(followUps.first { $0.id == "bonus" })
        let extra = try #require(followUps.first { $0.id == "extra" })
        #expect(first.shouldEnable(task: bonus))
        #expect(first.shouldEnable(task: extra))
    }

    /// A condition that cannot be evaluated closes no dependency cycle, as in the pair rules, so the other
    /// conditions still decide.
    @Test
    func conditionsThatCannotBeEvaluatedCloseNoCycle() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "flag", title: "", kind: .boolean),
                    .init(id: "first", title: "", kind: .boolean, enabledCondition: .any([
                        .responseValueComparison(taskId: "second", operator: .equal, value: .string("x")),
                        .responseValueComparison(taskId: "flag", operator: .equal, value: .bool(true))
                    ])),
                    .init(id: "second", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "first", operator: .equal, value: .bool(true)
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["flag"] = .init(value: .bool(true))
        #expect(try enabled("first", in: responses))
        #expect(try !enabled("second", in: responses))
        responses.responses["first"] = .init(value: .bool(true))
        #expect(try enabled("second", in: responses))
    }

    /// Such a condition adds no dependency either, so tasks that reference each other through it evaluate alike
    /// whichever of them is evaluated first, here through a group's condition.
    @Test
    func conditionsThatCannotBeEvaluatedAddNoDependency() throws {
        let firstIsTrue = GroveQuestionnaire.Questionnaire.Condition.responseValueComparison(taskId: "first", operator: .equal, value: .bool(true))
        var third = GroveQuestionnaire.Questionnaire.Task(id: "third", title: "", kind: .boolean, enabledCondition: firstIsTrue)
        third.groupPath = [.init(id: "group", condition: .responseValueComparison(taskId: "second", operator: .equal, value: .bool(true)))]
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "flag", title: "", kind: .boolean),
                    .init(id: "first", title: "", kind: .boolean, enabledCondition: .any([
                        .responseValueComparison(taskId: "second", operator: .equal, value: .string("x")),
                        .responseValueComparison(taskId: "flag", operator: .equal, value: .bool(true))
                    ])),
                    .init(id: "second", title: "", kind: .boolean, enabledCondition: firstIsTrue),
                    third
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        for id in ["flag", "first", "second"] {
            responses.responses[id] = .init(value: .bool(true))
        }
        #expect(try enabled("third", in: responses))
        #expect(try enabled("second", in: responses))
    }

    /// A custom question kind compares every value itself, so an ordered comparison on a string reads its
    /// enabled response.
    @Test
    func customKindsCompareEveryValueThemselves() throws {
        struct Config: QuestionKindConfig {}
        struct OrderedKind: QuestionKindDefinition {
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }

            static func evaluateResponseValueComparison(
                for config: Config,
                response: QuestionnaireResponses.Response.Value,
                operator: GroveQuestionnaire.Questionnaire.Condition.ComparisonOperator,
                value: GroveQuestionnaire.Questionnaire.Condition.Value
            ) -> Bool {
                guard case .string(let threshold) = value, let answer = response.stringValue, `operator` == .greaterThan else {
                    return false
                }
                return answer > threshold
            }
        }
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "section", tasks: [
                    .init(id: "custom", title: "", kind: .custom(OrderedKind.self, config: Config())),
                    .init(id: "later", title: "", kind: .boolean, enabledCondition: .responseValueComparison(
                        taskId: "custom", operator: .greaterThan, value: .string("b")
                    ))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["custom"] = .init(value: .string("c"))
        #expect(try enabled("later", in: responses))
        responses.responses["custom"] = .init(value: .string("a"))
        #expect(try !enabled("later", in: responses))
    }

    // MARK: Agreement with the pair rules

    /// A quantity condition orders the answers in its unit as the exported condition does the exported answers:
    /// by code and system, by unit text without a code, and a code without a system as unit text.
    @Test
    func quantityUnitIdentityAgreesWithThePairRules() throws {
        func quantity(_ value: Int, code: String? = nil, system: String? = nil, unit: String? = nil) -> QuestionnaireItemEnableWhen.AnswerX {
            .quantity(Quantity(
                code: code?.asFHIRStringPrimitive(),
                system: system.map { FHIRPrimitive(FHIRURI(stringLiteral: $0)) },
                unit: unit?.asFHIRStringPrimitive(),
                value: FHIRPrimitive(FHIRDecimal(Decimal(value)))
            ))
        }
        let ucum = "http://unitsofmeasure.org"
        func unit(_ url: String, code: String, system: String?, display: String) -> Extension {
            Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: url)),
                value: .coding(Coding(
                    code: code.asFHIRStringPrimitive(),
                    display: display.asFHIRStringPrimitive(),
                    system: system.map { FHIRPrimitive(FHIRURI(stringLiteral: $0)) }
                ))
            )
        }
        var weight = item("weight", .quantity)
        weight.extension = [unit("http://hl7.org/fhir/StructureDefinition/questionnaire-unit", code: "kg", system: ucum, display: "kilogram")]
        var dose = item("dose", .quantity)
        dose.extension = [unit("http://hl7.org/fhir/StructureDefinition/questionnaire-unit", code: "mg", system: nil, display: "milligram")]
        var height = item("height", .quantity)
        height.extension = [
            unit("http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption", code: "cm", system: ucum, display: "centimeter"),
            unit("http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption", code: "[in_i]", system: ucum, display: "inch")
        ]
        let cases: [(id: String, question: String, answer: QuestionnaireItemEnableWhen.AnswerX, operation: QuestionnaireItemOperator, enabled: Bool)] = [
            ("coded", "weight", quantity(80, code: "kg", system: ucum), .greaterThanOrEqual, true),
            ("code-takes-the-question-system", "weight", quantity(80, code: "kg"), .greaterThanOrEqual, true),
            ("unit-text", "weight", quantity(80, unit: "kilogram"), .greaterThanOrEqual, true),
            ("other-system", "weight", quantity(80, code: "kg", system: "https://example.org/units"), .greaterThanOrEqual, false),
            ("other-system-not-equal", "weight", quantity(85, code: "kg", system: "https://example.org/units"), .notEqual, false),
            ("without-unit", "weight", quantity(80), .greaterThanOrEqual, false),
            ("uncoded-unit-text", "dose", quantity(5, unit: "milligram"), .equal, true),
            ("code-without-system-is-text", "dose", quantity(5, code: "mg"), .equal, false),
            ("chosen-unit", "height", quantity(60, code: "[in_i]", system: ucum), .greaterThan, true),
            ("other-unit-option", "height", quantity(100, code: "cm", system: ucum), .lessThan, false)
        ]
        var targets = cases.map { entry in
            var target = item(entry.id, .boolean, when: [condition(entry.question, entry.operation, entry.answer)])
            target.required = true
            return target
        }
        targets.insert(contentsOf: [weight, dose, height], at: 0)
        let questionnaire = try questionnaire(targets)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(85))
        responses.responses["dose"] = .init(value: .number(5))
        responses.responses["height"] = .init(value: .quantity(70, unitCode: "[in_i]"))
        for entry in cases {
            #expect(try enabled(entry.id, in: responses) == entry.enabled, "\(entry.id)")
        }
        #expect(try disagreements(answeringEnabled: cases.map(\.id), in: responses).isEmpty)
    }

    /// A date-time condition keeps the offset and the fraction of a second it is written with, on import and on
    /// export, so it names the same instant as in the pair rules.
    @Test
    func dateTimeConditionsKeepTheirTimeZone() throws {
        func dateTime(_ text: String) throws -> QuestionnaireItemEnableWhen.AnswerX {
            .dateTime(FHIRPrimitive(try DateTime(text)))
        }
        let cases: [(id: String, condition: String, operation: QuestionnaireItemOperator, enabled: Bool)] = [
            ("after-ten-in-karachi", "2024-03-05T10:00:00+05:00", .greaterThan, true),
            ("before-eleven-in-karachi", "2024-03-05T11:00:00+05:00", .lessThan, true),
            ("at-the-instant-in-utc", "2024-03-05T05:30:00Z", .equal, true),
            ("before-a-fraction-later", "2024-03-05T05:30:00.5Z", .lessThan, true),
            ("not-a-fraction-later", "2024-03-05T05:30:00.5Z", .equal, false)
        ]
        var items = try cases.map { entry in
            var target = item(entry.id, .boolean, when: [condition("seen", entry.operation, try dateTime(entry.condition))])
            target.required = true
            return target
        }
        items.insert(item("seen", .dateTime), at: 0)
        let questionnaire = try questionnaire(items)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        // The participant's wall-clock time for 05:30 UTC, in whatever zone the device is in.
        let instant = try #require(ISO8601DateFormatter().date(from: "2024-03-05T05:30:00Z"))
        responses.responses["seen"] = .init(value: .date(Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)))
        for entry in cases {
            #expect(try enabled(entry.id, in: responses) == entry.enabled, "\(entry.id)")
        }
        #expect(try disagreements(answeringEnabled: cases.map(\.id), in: responses).isEmpty)
        let exported = try ModelsR4.Questionnaire(questionnaire)
        let karachi = exported.item?.first { $0.linkId.value?.string == "after-ten-in-karachi" }?.enableWhen?.first?.answer
        guard case .dateTime(let value)? = karachi else {
            Issue.record("Expected a dateTime condition")
            return
        }
        #expect(value.value?.timeZone?.secondsFromGMT() == 5 * 3_600)
        #expect(value.value?.time?.hour == 10)
    }

    /// The answers of a question whose enablement cannot be evaluated count as absent, as in the exported response,
    /// which omits the question, so a condition on it is decided as the pair rules decide it.
    @Test
    func sourcesWithUnknownEnablementAreDecidedAsThePairRulesDo() throws {
        let cases: [(id: String, answer: QuestionnaireItemEnableWhen.AnswerX, operation: QuestionnaireItemOperator, enabled: Bool)] = [
            ("not-true", .boolean(true), .notEqual, true),
            ("true", .boolean(true), .equal, false),
            ("missing", .boolean(false), .exists, true)
        ]
        var items = cases.map { entry in
            var target = item(entry.id, .boolean, when: [condition("cycle-a", entry.operation, entry.answer)])
            target.required = true
            return target
        }
        items.insert(contentsOf: [
            item("cycle-a", .boolean, when: [condition("cycle-b", .exists, .boolean(true))]),
            item("cycle-b", .boolean, when: [condition("cycle-a", .exists, .boolean(true))])
        ], at: 0)
        let questionnaire = try questionnaire(items)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["cycle-a"] = .init(value: .bool(true))
        responses.responses["cycle-b"] = .init(value: .bool(true))
        #expect(try !enabled("cycle-a", in: responses))
        for entry in cases {
            #expect(try enabled(entry.id, in: responses) == entry.enabled, "\(entry.id)")
        }
        #expect(try disagreements(answeringEnabled: cases.map(\.id), in: responses).isEmpty)
    }

    /// Exported answers follow the order of the options, which is the order conditions read them in.
    @Test
    func exportedAnswersFollowTheOptionOrder() throws {
        let questionnaire = try codingQuestionnaire()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["color"] = .init(value: .choice(.init(selectedOptions: ["red", "\(Self.colors)|blue", "\(Self.colors)|red"])))
        let exported = try ModelsR4.QuestionnaireResponse(
            responses,
            renderedIn: questionnaireResponseTestLocale,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        let codes = (exported.item?.first { $0.linkId.value?.string == "color" }?.answer ?? []).map { answer -> String in
            guard case .coding(let coding)? = answer.value else {
                return "?"
            }
            return [coding.system?.value?.url.absoluteString, coding.code?.value?.string].compactMap(\.self).joined(separator: "|")
        }
        #expect(codes == ["\(Self.colors)|red", "\(Self.colors)|blue", "red"])
    }
}


extension EnableWhenTests {
    private func item(
        _ linkId: String,
        _ type: QuestionnaireItemType,
        when conditions: [QuestionnaireItemEnableWhen] = []
    ) -> ModelsR4.QuestionnaireItem {
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: FHIRPrimitive(type))
        item.text = linkId.asFHIRStringPrimitive()
        item.enableWhen = conditions.isEmpty ? nil : conditions
        return item
    }

    private func condition(
        _ question: String,
        _ operation: QuestionnaireItemOperator,
        _ answer: QuestionnaireItemEnableWhen.AnswerX
    ) -> QuestionnaireItemEnableWhen {
        QuestionnaireItemEnableWhen(answer: answer, operator: FHIRPrimitive(operation), question: question.asFHIRStringPrimitive())
    }

    private func questionnaire(_ items: [ModelsR4.QuestionnaireItem]) throws -> GroveQuestionnaire.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.language = "en-US"
        questionnaire.url = "https://example.org/fhir/Questionnaire/enable-when".asFHIRURIPrimitive()
        questionnaire.version = "1.0.0".asFHIRStringPrimitive()
        questionnaire.item = items
        return try GroveQuestionnaire.Questionnaire(questionnaire, clock: questionnaireResponseTestClock)
    }

    /// A repeating choice with red and blue in one system and red without a system, gated by coding conditions.
    private func codingQuestionnaire() throws -> GroveQuestionnaire.Questionnaire {
        func coding(_ code: String, system: String?) -> Coding {
            Coding(code: code.asFHIRStringPrimitive(), system: system.map { FHIRPrimitive(FHIRURI(stringLiteral: $0)) })
        }
        var color = item("color", .choice)
        color.repeats = true
        color.answerOption = [
            .init(value: .coding(coding("red", system: Self.colors))),
            .init(value: .coding(coding("blue", system: Self.colors))),
            .init(value: .coding(coding("red", system: nil)))
        ]
        return try questionnaire([
            color,
            item("with-system", .display, when: [condition("color", .equal, .coding(coding("red", system: Self.colors)))]),
            item("without-system", .display, when: [condition("color", .equal, .coding(coding("red", system: nil)))]),
            item("other-system", .display, when: [condition("color", .equal, .coding(coding("red", system: "http://other.example/colors")))]),
            item("not-blue", .display, when: [condition("color", .notEqual, .coding(coding("blue", system: Self.colors)))]),
            item("not-red-without-system", .display, when: [condition("color", .notEqual, .coding(coding("red", system: nil)))])
        ])
    }

    /// Answers every enabled one of the boolean `targets` and returns the pair issues that disagree with the
    /// enablement on the device: an exported item that is disabled, or an enabled required item that is missing.
    private func disagreements(answeringEnabled targets: [String], in responses: QuestionnaireResponses) throws -> [ValidationIssue] {
        for target in targets where try enabled(target, in: responses) {
            responses.responses[target] = .init(value: .bool(true))
        }
        // The resources are exported one by one: the pair builder refuses a pair with a condition it cannot evaluate.
        let questionnaire = try ModelsR4.Questionnaire(responses.questionnaire)
        let response = try ModelsR4.QuestionnaireResponse(
            responses,
            renderedIn: questionnaireResponseTestLocale,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        return PairValidator().issues(questionnaire: questionnaire, response: response)
            .filter { $0.code == .itemDisabled || $0.code == .requiredItem }
    }

    private func enabled(_ taskId: String, in responses: QuestionnaireResponses) throws -> Bool {
        let task = try #require(responses.questionnaire.sections.flatMap(\.tasks).first { $0.id == taskId })
        return responses.shouldEnable(task: task)
    }
}
