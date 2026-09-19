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
import Testing


@Suite
struct ScopedExpressionCacheTests {
    private struct Fixture {
        let root: QuestionnaireResponses
        let inner: QuestionnaireResponses
        let child: Questionnaire.Task
        let later: Questionnaire.Task

        init() throws {
            let codeSystem = try #require(URL(string: "https://example.org/choice"))
            let flag = Questionnaire.Task(id: "flag", title: "Flag", kind: .boolean)
            child = .init(id: "child", title: "Child", kind: .boolean, enabledCondition: .expression("true"))
            let parent = Questionnaire.Task(id: "parent", title: "Parent", kind: .choice(.init(
                options: [.init(id: "yes", title: "Yes", fhirCoding: .init(system: codeSystem, code: "yes"))],
                allowsMultipleSelection: false,
                followUpTasks: [child]
            )))
            later = .init(id: "later", title: "Later", kind: .boolean, enabledCondition: .expression(
                "%resource.item.where(linkId='flag').answer.value = true"
            ))
            let questionnaire = try Questionnaire(
                metadata: .init(id: "scoped-cache", url: URL(string: "https://example.org/scoped-cache"), title: "Scoped cache", explainer: ""),
                sections: [.init(id: "section", tasks: [flag, parent, later])]
            ).withExpressionEngine()
            root = QuestionnaireResponses(questionnaire: questionnaire)
            root.responses["flag"] = .init(value: .bool(true))
            root.responses["parent"] = .init(value: .choice(.init(selectedOptions: ["yes"])))
            root.responses["later"] = .init(value: .bool(true))
            inner = root.view(appending: QuestionnaireResponses.ResponsePath(taskId: "parent").appending(choiceOption: "yes"))
            inner.responses["child"] = .init(value: .bool(true))
        }
    }

    private static func flagQuestionnaire() throws -> Questionnaire {
        try Questionnaire(
            metadata: .init(id: "cache-identity", url: nil, title: "Cache identity", explainer: ""),
            sections: [.init(id: "section", tasks: [.init(id: "flag", title: "Flag", kind: .boolean)])]
        ).withExpressionEngine()
    }

    private static func expectIndependentResults(first: QuestionnaireResponses, second: QuestionnaireResponses) throws {
        let engine = try #require(first.questionnaire.expressionEngine as? FHIRQuestionnaireExpressionEngine)
        #expect(engine === second.questionnaire.expressionEngine)
        let expression = "%resource.item.where(linkId='flag').answer.value = true"
        #expect(try engine.evaluateBoolean(expression, scope: .item("flag"), in: first) == .true)
        let firstBuilds = engine.work.encodedStates
        #expect(try engine.evaluateBoolean(expression, scope: .item("flag"), in: first) == .true)
        #expect(engine.work.encodedStates == firstBuilds)
        #expect(try engine.evaluateBoolean(expression, scope: .item("flag"), in: second) == .false)
        #expect(try engine.evaluateBoolean(expression, scope: .item("flag"), in: first) == .true)
    }

    @Test
    func evaluatingNestedViewDoesNotDisableRootTask() throws {
        let fixture = try Fixture()
        #expect(fixture.inner.shouldEnable(task: fixture.child))
        #expect(fixture.root.shouldEnable(task: fixture.later))
    }

    @Test
    func purgingNestedQuestionsDoesNotDeleteEnabledRootAnswer() throws {
        let fixture = try Fixture()
        fixture.root.purgeResponsesToDisabledTasks()
        #expect(fixture.root.responses["later"].value == .bool(true))
    }

    @Test
    func nestedEditsInvalidateTheSharedResource() throws {
        let fixture = try Fixture()
        let engine = try #require(fixture.root.questionnaire.expressionEngine as? FHIRQuestionnaireExpressionEngine)
        let expression = "%resource.descendants().where(linkId='child').answer.value = true"
        #expect(try engine.evaluateBoolean(expression, scope: .item("child"), in: fixture.inner) == .true)
        let encodedStates = engine.work.encodedStates
        #expect(try engine.evaluateBoolean(expression, scope: .item("child"), in: fixture.root) == .true)
        #expect(engine.work.encodedStates == encodedStates)
        fixture.inner.responses["child"] = .init(value: .bool(false))
        #expect(try engine.evaluateBoolean(expression, scope: .item("child"), in: fixture.inner) == .false)
        #expect(try engine.evaluateBoolean(expression, scope: .item("child"), in: fixture.root) == .false)
        #expect(engine.work.encodedStates == encodedStates + 1)
    }

    @Test
    func independentRootsDoNotShareResultsAfterTheSameNumberOfEdits() throws {
        let questionnaire = try Self.flagQuestionnaire()
        let first = QuestionnaireResponses(questionnaire: questionnaire)
        let second = QuestionnaireResponses(questionnaire: questionnaire)
        first.responses["flag"] = .init(value: .bool(true))
        second.responses["flag"] = .init(value: .bool(false))
        try Self.expectIndependentResults(first: first, second: second)
    }

    @Test
    func restoredDraftsWithTheSameResponseIdDoNotShareResults() throws {
        let questionnaire = try Self.flagQuestionnaire()
        let original = QuestionnaireResponses(questionnaire: questionnaire)
        original.responses["flag"] = .init(value: .bool(false))
        let draft = try original.draft()
        let first = try QuestionnaireResponses(questionnaire: questionnaire, resuming: draft)
        let second = try QuestionnaireResponses(questionnaire: questionnaire, resuming: draft)
        #expect(first.id == second.id)
        #expect(first.id == original.id)
        first.responses["flag"] = .init(value: .bool(true))
        second.responses["flag"] = .init(value: .bool(false))
        try Self.expectIndependentResults(first: first, second: second)
    }
}
