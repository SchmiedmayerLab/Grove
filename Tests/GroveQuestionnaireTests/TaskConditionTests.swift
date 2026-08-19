//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
import Testing


@Suite
struct TaskConditionTests {
    private typealias C = Questionnaire.Condition // swiftlint:disable:this type_name
    
    @Test
    func conditionSimplification() {
        do {
            let input: C = .all([.all([.all([]), .all([])]), .all([])])
            #expect(input.simplified() == .none)
        }
    }
    
    
    @Test
    func hashingAndEquality() {
        let cond1: C = .all([true, false])
        let cond2: C = .all([false, true])
        #expect(cond1 == cond2)
        #expect(cond1.hashValue == cond2.hashValue)
        
        #expect(C.all([true, false]) == false)
        #expect(C.any([true, false]) == true)
        #expect(C.all([true, .true && .false]) == false)
        #expect(C.all([true, .false || .false]) == false)
        #expect(C.all([true, .false || .true]) == true)
        #expect(C.all([true, !(.false || .true)]) == false)
    }
    
    @Test
    func nestedTaskConditionLookup() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "", tasks: [
                    .init(id: "task0", title: "Task0", kind: .boolean),
                    .init(
                        id: "task1",
                        title: "Exercise Preferences",
                        kind: .choice(.init(
                            options: [
                                .init(id: "running", title: "Running"),
                                .init(id: "cycling", title: "Cycling")
                            ],
                            allowsMultipleSelection: true,
                            followUpTasks: [
                                .init(
                                    id: "joy",
                                    title: "Do you enjoy this activity?",
                                    kind: .boolean,
                                    enabledCondition: .responseValueComparison(taskId: "task0", operator: .equal, value: .bool(true))
                                )
                            ]
                        ))
                    )
                ])
            ]
        )
        let rootTask0 = try #require(questionnaire.task(at: ["task0"]))
        let rootTask1 = try #require(questionnaire.task(at: ["task1"]))
        let innerTask = try #require(questionnaire.task(at: ["task1", "joy"]))
        let rootResponses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(rootResponses.shouldEnable(task: rootTask0))
        #expect(rootResponses.shouldEnable(task: rootTask1))
        
        rootResponses.responses[rootTask0.id].value.boolValue = true
        
        rootResponses.responses[rootTask1.id].value.choiceValue.select("running")
        let innerResponses = rootResponses.view(
            appending: .init().appending(taskId: rootTask1.id).appending(choiceOption: "running")
        )
        #expect(innerResponses.shouldEnable(task: innerTask))
        rootResponses.responses[rootTask0.id].value.boolValue = false
        #expect(!innerResponses.shouldEnable(task: innerTask))
        rootResponses.responses[rootTask0.id].value.boolValue = true
        #expect(innerResponses.shouldEnable(task: innerTask))
    }
    
    
    /// FHIR's `enableWhen` places no ordering restriction on references: a question gated on a
    /// *later* one is asked as soon as that answer arrives, and then owes an answer of its own.
    @Test
    func forwardReferencingConditionIsAskedAndBlocksTheSection() throws {
        let section = Questionnaire.Section(id: "s0", tasks: [
            .init(id: "t0A", title: "Section A", kind: .instructional("")),
            .init(
                id: "t1A",
                title: "How much do you like green?",
                kind: .choice(.init(options: [.init(id: "0", title: "A Lot")], allowsMultipleSelection: false)),
                enabledCondition: .responseValueComparison(taskId: "t2A", operator: .equal, value: .SCMCOption(id: "green"))
            ),
            .init(
                id: "t2A",
                title: "What's your favourite Colour?",
                kind: .choice(.init(
                    options: [.init(id: "red", title: "Red"), .init(id: "green", title: "Green")],
                    allowsMultipleSelection: false
                ))
            )
        ])
        let questionnaire = Questionnaire(metadata: .init(id: "", url: nil, title: "", explainer: ""), sections: [section])
        let t1A = try #require(questionnaire.task(at: ["t1A"]))
        let t2A = try #require(questionnaire.task(at: ["t2A"]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(!responses.shouldEnable(task: t1A))

        responses.responses[t2A.id].value.choiceValue.select("green")
        #expect(responses.shouldEnable(task: t1A))
        #expect(!responses.isComplete(in: section))
        #expect(responses.firstTaskPreventingCompletion(of: section) == t1A)

        responses.responses[t1A.id].value.choiceValue.select("0")
        #expect(responses.isComplete(in: section))
    }


    @Test
    func responseExportSkipsDisabledTasks() throws {
        let questionnaire = Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "s0", tasks: [
                    .init(id: "t0", title: "", kind: .boolean),
                    .init(
                        id: "t1",
                        title: "",
                        kind: .freeText(.init()),
                        enabledCondition: .responseValueComparison(taskId: "t0", operator: .equal, value: .bool(true))
                    )
                ])
            ]
        )
        let rootTask0 = try #require(questionnaire.task(at: ["t0"]))
        let rootTask1 = try #require(questionnaire.task(at: ["t1"]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.shouldEnable(task: rootTask0))
        #expect(!responses.shouldEnable(task: rootTask1))
        
        responses.responses[rootTask0.id].value.boolValue = true
        #expect(responses.shouldEnable(task: rootTask1))
        
        responses.responses[rootTask1.id].value.stringValue = "Hello World"
        #expect(responses.responses == .init([
            rootTask0.id: .init(value: .bool(true)),
            rootTask1.id: .init(value: .string("Hello World"))
        ]))
        responses.purgeResponsesToDisabledTasks()
        #expect(responses.responses == .init([
            rootTask0.id: .init(value: .bool(true)),
            rootTask1.id: .init(value: .string("Hello World"))
        ]))
        
        responses.responses[rootTask0.id].value.boolValue = false
        #expect(!responses.shouldEnable(task: rootTask1))
        #expect(responses.responses == .init([
            rootTask0.id: .init(value: .bool(false)),
            rootTask1.id: .init(value: .string("Hello World"))
        ]))
        responses.purgeResponsesToDisabledTasks()
        #expect(responses.responses == .init([
            rootTask0.id: .init(value: .bool(false))
        ]))
    }
}
