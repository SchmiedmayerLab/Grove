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


/// The bar counts questions and page turns, and never moves back while the participant answers forward.
@Suite
struct PageProgressTests {
    /// An intake with a yes/no flag, one page for each answer, and a closing page for everyone.
    private static let fixture = """
    {
      "resourceType": "Questionnaire",
      "id": "progress",
      "status": "active",
      "item": [
        { "linkId": "intake", "type": "group", "text": "Intake", "item": [
          { "linkId": "flag", "type": "boolean", "text": "Flag?" }
        ] },
        { "linkId": "yes", "type": "group", "text": "Yes",
          "enableWhen": [{ "question": "flag", "operator": "=", "answerBoolean": true }],
          "item": [{ "linkId": "yes.1", "type": "boolean", "text": "Yes 1" }] },
        { "linkId": "no", "type": "group", "text": "No",
          "enableWhen": [{ "question": "flag", "operator": "=", "answerBoolean": false }],
          "item": [{ "linkId": "no.1", "type": "boolean", "text": "No 1" }] },
        { "linkId": "closing", "type": "group", "text": "Closing", "item": [
          { "linkId": "closing.1", "type": "boolean", "text": "Closing 1" }
        ] }
      ]
    }
    """

    /// The same shape, gated by an expression that has nothing to evaluate over until the flag is answered.
    private static let expressionFixture = fixture
        .replacingOccurrences(of: "\"id\": \"progress\"", with: "\"id\": \"progress-expression\"")
        .replacingOccurrences(
            of: "\"enableWhen\": [{ \"question\": \"flag\", \"operator\": \"=\", \"answerBoolean\": true }],",
            with: """
            "extension": [{ "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
              "valueExpression": { "language": "text/fhirpath", "expression": "%resource.descendants().where(linkId='flag').answer.value = true" } }],
            """
        )
        .replacingOccurrences(
            of: "\"enableWhen\": [{ \"question\": \"flag\", \"operator\": \"=\", \"answerBoolean\": false }],",
            with: """
            "extension": [{ "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
              "valueExpression": { "language": "text/fhirpath", "expression": "%resource.descendants().where(linkId='flag').answer.value = false" } }],
            """
        )

    private static func responses(_ json: String) throws -> QuestionnaireResponses {
        let questionnaire = try GroveQuestionnaire.Questionnaire(JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(json.utf8)))
        return QuestionnaireResponses(questionnaire: questionnaire)
    }

    private static func section(_ id: String, of responses: QuestionnaireResponses) throws -> GroveQuestionnaire.Questionnaire.Section {
        try #require(responses.questionnaire.sections.first { $0.id == id })
    }

    private static func progress(at id: String, of responses: QuestionnaireResponses) throws -> ProgressCount {
        try responses.progress(at: section(id, of: responses), in: responses.questionnaire.sections)
    }

    @Test(arguments: [fixture, expressionFixture])
    func undecidedQuestionsCountUntilAnAnswerRulesThemOut(json: String) throws {
        let responses = try Self.responses(json)
        // Nothing answered: both gated pages may still come, so four questions and three pages lie ahead.
        #expect(try Self.progress(at: "intake", of: responses) == ProgressCount(completed: 0, remaining: 7))

        responses.responses["flag"] = .init(value: .bool(true))
        // The answer is done and rules one page out, on the spot: its question and its turn.
        #expect(try Self.progress(at: "intake", of: responses) == ProgressCount(completed: 1, remaining: 4))
        // Turning the page is a step of its own.
        #expect(try Self.progress(at: "yes", of: responses) == ProgressCount(completed: 2, remaining: 3))
        responses.responses["yes.1"] = .init(value: .bool(true))
        #expect(try Self.progress(at: "yes", of: responses) == ProgressCount(completed: 3, remaining: 2))
        #expect(try Self.progress(at: "closing", of: responses) == ProgressCount(completed: 4, remaining: 1))
        responses.responses["closing.1"] = .init(value: .bool(false))
        #expect(try Self.progress(at: "closing", of: responses).fraction == 1)
    }

    /// A question left unanswered on a page already passed is behind the participant, and counts as done.
    @Test
    func aQuestionLeftBehindCountsAsDone() throws {
        let responses = try Self.responses(Self.fixture)
        responses.responses["flag"] = .init(value: .bool(true))
        #expect(try Self.progress(at: "closing", of: responses) == ProgressCount(completed: 4, remaining: 1))
    }

    /// Going back to an earlier page keeps the answers given after it in the count, so the bar stays put.
    @Test
    func answersOnLaterPagesStayCounted() throws {
        let responses = try Self.responses(Self.fixture)
        responses.responses["flag"] = .init(value: .bool(true))
        responses.responses["yes.1"] = .init(value: .bool(true))
        #expect(try Self.progress(at: "intake", of: responses) == ProgressCount(completed: 2, remaining: 3))
    }

    /// A note asks nothing and is no step, but reaching its page is one; a closing note sits on a full bar.
    @Test
    func notesAreNotCounted() throws {
        let json = Self.fixture.replacingOccurrences(
            of: "\"linkId\": \"closing.1\", \"type\": \"boolean\", \"text\": \"Closing 1\"",
            with: "\"linkId\": \"closing.1\", \"type\": \"display\", \"text\": \"Thank you.\""
        )
        let responses = try Self.responses(json)
        responses.responses["flag"] = .init(value: .bool(true))
        #expect(try Self.progress(at: "yes", of: responses) == ProgressCount(completed: 2, remaining: 2))
        responses.responses["yes.1"] = .init(value: .bool(true))
        #expect(try Self.progress(at: "yes", of: responses) == ProgressCount(completed: 3, remaining: 1))
        #expect(try Self.progress(at: "closing", of: responses).fraction == 1)
    }

    @Test
    func aSkippedPageIsNotCounted() throws {
        let responses = try Self.responses(Self.fixture)
        responses.responses["flag"] = .init(value: .bool(false))
        #expect(try Self.progress(at: "no", of: responses) == ProgressCount(completed: 2, remaining: 3))
    }

    /// An answer the page will not accept, such as a number past its bound, is a step still ahead.
    @Test
    func anAnswerThePageRejectsIsStillAhead() throws {
        let json = Self.fixture.replacingOccurrences(
            of: "{ \"linkId\": \"closing.1\", \"type\": \"boolean\", \"text\": \"Closing 1\" }",
            with: """
            { "linkId": "closing.1", "type": "integer", "text": "Closing 1",
              "extension": [{ "url": "http://hl7.org/fhir/StructureDefinition/maxValue", "valueInteger": 5 }] }
            """
        )
        let responses = try Self.responses(json)
        responses.responses["flag"] = .init(value: .bool(true))
        responses.responses["closing.1"] = .init(value: .number(10))
        #expect(try Self.progress(at: "closing", of: responses) == ProgressCount(completed: 4, remaining: 1))
        responses.responses["closing.1"] = .init(value: .number(5))
        #expect(try Self.progress(at: "closing", of: responses).fraction == 1)
    }

    /// A page outside the run, as on a follow-up sheet, reports a run barely begun rather than one done.
    @Test
    func aPageOutsideTheRunIsNotDone() throws {
        let responses = try Self.responses(Self.fixture)
        let intake = try Self.section("intake", of: responses)
        #expect(responses.progress(at: intake, in: []) == ProgressCount(completed: 0, remaining: 1))
    }

    /// A questionnaire that asks nothing is complete from its first page.
    @Test
    func aQuestionnaireWithNothingToAskIsComplete() throws {
        let json = """
        { "resourceType": "Questionnaire", "id": "notes", "status": "active", "item": [
          { "linkId": "note", "type": "group", "text": "Note", "item": [
            { "linkId": "note.1", "type": "display", "text": "Nothing to answer." } ] } ] }
        """
        let responses = try Self.responses(json)
        #expect(try Self.progress(at: "note", of: responses) == ProgressCount(completed: 0, remaining: 0))
        #expect(try Self.progress(at: "note", of: responses).fraction == 1)
    }

    @Test
    func theFractionOnlyGrowsAlongTheRun() throws {
        let responses = try Self.responses(Self.fixture)
        let start = try Self.progress(at: "intake", of: responses).fraction
        responses.responses["flag"] = .init(value: .bool(true))
        let afterAnswering = try Self.progress(at: "intake", of: responses).fraction
        let second = try Self.progress(at: "yes", of: responses).fraction
        responses.responses["yes.1"] = .init(value: .bool(true))
        let afterTheSecond = try Self.progress(at: "yes", of: responses).fraction
        #expect(start == 0)
        #expect(afterAnswering > start)
        #expect(second > afterAnswering, "turning the page is a step")
        #expect(afterTheSecond > second)
        #expect(afterTheSecond < 1, "one page is still ahead")
    }
}
