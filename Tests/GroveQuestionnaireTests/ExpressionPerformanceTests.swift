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


/// A questionnaire that leans on expressions everywhere a form can: variables over the whole response, pages and
/// questions gated by them, nested groups, scores and an outcome computed from the rest. Every render of a page
/// asks the engine about every task, so the engine has to answer from what it already knows.
@Suite(.timeLimit(.minutes(2)))
struct ExpressionPerformanceTests {
    private static let questionsPerPage = 8
    private static let codeSystem = "https://example.org/yes-no"
    /// The sizes the budgets are set for: a long intake, and one four times as long, which may take four times as long.
    private static let sizes = [12, 48]
    /// A frame on a ProMotion display, the shortest the main thread gets between two renders.
    private static let frame = Swift.Duration.milliseconds(1000.0 / 120)

    /// The questionnaire, generated: `pages` pages of `questionsPerPage` yes/no questions each, plus a number, a
    /// nested pair of follow-ups, a score per page and one outcome.
    private static func fixture(pages: Int) -> String {
        func yesNo(_ linkId: String, text: String, gate: String? = nil) -> String {
            let extensions = gate.map {
                """
                "extension": [{ "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
                  "valueExpression": { "language": "text/fhirpath", "expression": "\($0)" } }],
                """
            } ?? ""
            return """
            { "linkId": "\(linkId)", "text": "\(text)", "type": "choice", "required": true, \(extensions)
              "answerOption": [
                { "valueCoding": { "system": "\(codeSystem)", "code": "yes", "display": "Yes" },
                  "extension": [{ "url": "http://hl7.org/fhir/StructureDefinition/ordinalValue", "valueDecimal": 1 }] },
                { "valueCoding": { "system": "\(codeSystem)", "code": "no", "display": "No" },
                  "extension": [{ "url": "http://hl7.org/fhir/StructureDefinition/ordinalValue", "valueDecimal": 0 }] }
              ] }
            """
        }
        func answered(_ linkIds: [String]) -> String {
            "%resource.descendants().where(" + linkIds.map { "linkId='\($0)'" }.joined(separator: " or ") + ").answer.value"
        }
        // Ten variables: half read answers across the form, half combine the others.
        var variables: [String] = []
        for index in 0..<5 {
            let linkIds = (0..<pages).map { "p\($0).q\(index + 1)" }
            variables.append("{ \"name\": \"v\(index)\", \"expression\": \"\(answered(linkIds)).where(code='yes').exists()\" }")
        }
        variables.append("{ \"name\": \"v5\", \"expression\": \"%v0 and %v1.not()\" }")
        variables.append("{ \"name\": \"v6\", \"expression\": \"%v2 or %v3\" }")
        variables.append("{ \"name\": \"v7\", \"expression\": \"%v4 and %v5.not() and %v6\" }")
        variables.append("{ \"name\": \"v8\", \"expression\": \"%v0 or %v7\" }")
        variables.append("{ \"name\": \"v9\", \"expression\": \"%v8.not()\" }")
        let variableExtensions = variables.map {
            "{ \"url\": \"http://hl7.org/fhir/StructureDefinition/variable\", \"valueExpression\": { \"language\": \"text/fhirpath\", " + $0.dropFirst() + " }"
        }
        var pageItems: [String] = []
        for page in 0..<pages {
            var items: [String] = []
            for question in 1...questionsPerPage {
                // Every other question is gated on a variable and on the answer before it.
                let gate = question.isMultiple(of: 2)
                    ? "%v\((page + question) % 10) or \(answered(["p\(page).q\(question - 1)"])).where(code='yes').exists()"
                    : nil
                items.append(yesNo("p\(page).q\(question)", text: "Page \(page), question \(question)", gate: gate))
            }
            items.append("""
            { "linkId": "p\(page).n", "text": "How many?", "type": "integer" }
            """)
            items.append("""
            { "linkId": "p\(page).g", "text": "More on the first answer", "type": "group",
              "extension": [{ "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
                "valueExpression": { "language": "text/fhirpath", "expression": "\(answered(["p\(page).q1"])).where(code='yes').exists()" } }],
              "item": [ \(yesNo("p\(page).g.a", text: "Really?")), \(yesNo("p\(page).g.b", text: "Still?", gate: "%v\(page % 10)")) ] }
            """)
            let scored = (1...questionsPerPage).map { "p\(page).q\($0)" }
            items.append("""
            { "linkId": "p\(page).score", "text": "Score", "type": "integer",
              "extension": [
                { "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden", "valueBoolean": true },
                { "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                  "valueExpression": { "language": "text/fhirpath", "expression": "\(answered(scored).replacingOccurrences(of: ".answer.value", with: ".answer")).weight().sum()" } } ] }
            """)
            // The first page is always asked; every later one hangs on a variable.
            let gate = page == 0 ? "" : """
            "extension": [{ "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
              "valueExpression": { "language": "text/fhirpath", "expression": "%v\(page % 10).not() or %v\((page + 3) % 10)" } }],
            """
            pageItems.append("""
            { "linkId": "p\(page)", "text": "Page \(page)", "type": "group", \(gate) "item": [ \(items.joined(separator: ",\n")) ] }
            """)
        }
        pageItems.append("""
        { "linkId": "outcome", "text": "Outcome", "type": "choice",
          "extension": [
            { "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden", "valueBoolean": true },
            { "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
              "valueExpression": { "language": "text/fhirpath", "expression": "iif(%v7, 'stop', iif(%v8, 'review', 'go'))" } } ],
          "answerOption": [
            { "valueCoding": { "system": "https://example.org/outcome", "code": "go" } },
            { "valueCoding": { "system": "https://example.org/outcome", "code": "review" } },
            { "valueCoding": { "system": "https://example.org/outcome", "code": "stop" } } ] }
        """)
        return """
        { "resourceType": "Questionnaire", "id": "expressions", "url": "https://example.org/Questionnaire/expressions", "status": "active", "title": "Expressions everywhere",
          "extension": [ \(variableExtensions.joined(separator: ",\n")) ],
          "item": [ \(pageItems.joined(separator: ",\n")) ] }
        """
    }

    private static func responses(pages: Int = 12) throws -> QuestionnaireResponses {
        let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(fixture(pages: pages).utf8))
        return QuestionnaireResponses(questionnaire: try GroveQuestionnaire.Questionnaire(resource))
    }

    /// A budget that grows with the questionnaire: `base` for twelve pages.
    private static func budget(_ base: Swift.Duration, pages: Int) -> Swift.Duration {
        base * pages / 12
    }

    private static func answer(_ linkId: String, yes: Bool, in responses: QuestionnaireResponses) {
        responses.responses[linkId] = .init(value: .choice(.init(selectedOptions: ["\(codeSystem)|\(yes ? "yes" : "no")"])))
    }

    /// One pass over every task, the way a page asks on each render.
    @discardableResult
    private static func pass(over responses: QuestionnaireResponses) -> Int {
        responses.questionnaire.sections.flatMap(\.tasks).count { responses.shouldEnable(task: $0) }
    }

    private static func pageIsShown(_ page: Int, in responses: QuestionnaireResponses) -> Bool {
        let first = responses.questionnaire.sections.flatMap(\.tasks).first { $0.id == "p\(page).q1" }
        return first.map { responses.shouldEnable(task: $0) } ?? false
    }

    @Test(arguments: sizes)
    func theFixtureIsAsHeavyAsMeant(pages: Int) throws {
        let responses = try Self.responses(pages: pages)
        let tasks = responses.questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.count == pages * (Self.questionsPerPage + 4) + 1)
        #expect(tasks.count { $0.calculatedExpression != nil } == pages + 1)
        #expect(responses.questionnaire.expressionEngine != nil)
    }

    /// The engine parses each expression once and encodes the answers once per state, however often a page asks.
    @Test(arguments: sizes)
    func theEngineWorksOncePerStateOfTheAnswers(pages: Int) throws {
        let responses = try Self.responses(pages: pages)
        let engine = try #require(responses.questionnaire.expressionEngine as? FHIRQuestionnaireExpressionEngine)
        Self.pass(over: responses)
        let afterFirstPass = engine.work
        #expect(afterFirstPass.encodedStates <= 2, "the initial recalculation and the first render")
        for _ in 0..<20 {
            Self.pass(over: responses)
        }
        #expect(engine.work == afterFirstPass, "twenty more renders neither parse nor encode")
        // The first answer is the first recalculation, which parses the calculated expressions; later ones parse nothing.
        Self.answer("p0.q1", yes: true, in: responses)
        Self.pass(over: responses)
        let afterFirstAnswer = engine.work
        Self.answer("p1.q1", yes: true, in: responses)
        Self.pass(over: responses)
        let afterSecondAnswer = engine.work
        #expect(afterSecondAnswer.parsedExpressions == afterFirstAnswer.parsedExpressions, "an answer parses nothing new")
        #expect(afterSecondAnswer.encodedStates - afterFirstAnswer.encodedStates <= 2, "the recalculation's pass and its check")
    }

    /// A render pass over the form is answered from what the engine remembers: a ProMotion frame for twelve pages on
    /// a runner slower and busier than a phone, against a pass that evaluates, which is tens of times slower.
    @Test(arguments: sizes)
    func aRenderPassIsQuick(pages: Int) throws {
        let responses = try Self.responses(pages: pages)
        Self.pass(over: responses)
        let steady = ContinuousClock().measure {
            for _ in 0..<20 {
                Self.pass(over: responses)
            }
        } / 20
        #expect(steady < Self.budget(Self.frame, pages: pages), "a pass over \(pages) pages took \(steady)")
    }

    /// An answer encodes the form twice, once to recompute every score and once to see them settle, and the render
    /// after it evaluates every gate anew: eight ProMotion frames for twelve pages on the runner, where it takes
    /// about four, against the hundreds an encoding per calculated item cost. The quickest of three rounds counts,
    /// so tests running alongside do not read as a regression; the shipped intake is held to a frame in Plainly.
    @Test(arguments: sizes)
    func anAnswerReachesTheNextRenderQuickly(pages: Int) throws {
        let responses = try Self.responses(pages: pages)
        Self.pass(over: responses)
        var perAnswer = Swift.Duration.seconds(1)
        for round in 0..<3 {
            let measured = ContinuousClock().measure {
                for page in 0..<pages {
                    Self.answer("p\(page).q1", yes: (page + round).isMultiple(of: 2), in: responses)
                    Self.pass(over: responses)
                }
            } / pages
            perAnswer = min(perAnswer, measured)
        }
        #expect(perAnswer < Self.budget(Self.frame * 8, pages: pages), "answering and re-rendering \(pages) pages took \(perAnswer) per answer")
    }

    /// What the engine remembers follows the answers: a page opens and closes with the variable it hangs on.
    @Test
    func rememberedResultsFollowTheAnswers() throws {
        let responses = try Self.responses()
        // Page 1 shows unless %v1 holds, or when %v4 does.
        #expect(Self.pageIsShown(1, in: responses))
        for page in 0..<12 {
            Self.answer("p\(page).q2", yes: true, in: responses)
        }
        #expect(!Self.pageIsShown(1, in: responses), "every q2 answered yes sets %v1")
        Self.answer("p0.q5", yes: true, in: responses)
        #expect(Self.pageIsShown(1, in: responses), "%v4 opens it again")
        #expect(responses.responses["outcome"].value == .choice(.init(selectedOptions: ["https://example.org/outcome|go"])))
        // %v7 needs %v4, %v6 and not %v5: the first answer sets %v0 without %v5, the third sets %v2.
        Self.answer("p0.q1", yes: true, in: responses)
        Self.answer("p0.q3", yes: true, in: responses)
        #expect(responses.responses["p0.score"].value == .number(4), "the score counts the yeses on its page")
        #expect(responses.responses["outcome"].value == .choice(.init(selectedOptions: ["https://example.org/outcome|stop"])))
    }
}
