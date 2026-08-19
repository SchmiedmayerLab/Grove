//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRQuestionnaires
import Foundation
@testable import GroveQuestionnaire
import GroveQuestionnaireCatalog
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


@Suite
struct FHIRConversionTests {
    @Test
    func convertFromFHIR() throws {
        let allR4Inputs = ModelsR4.Questionnaire.exampleQuestionnaires + ModelsR4.Questionnaire.researchQuestionnaires
        for input in allR4Inputs {
            // simply test that we can import all of the sample questionnaires without failure
            // IDEA maybe also test that they are what we expect
            _ = try GroveQuestionnaire.Questionnaire(input)
        }
    }
    
    
    @Test
    func convertToFHIR() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire.phq9
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        for task in questionnaire.sections.flatMap(\.tasks) {
            switch task.kind.variant {
            case .instructional:
                break // ignore
            case .choice(let config):
                let id = try #require(config.options.last).id
                responses.responses[task.id].value.choiceValue.select(id)
            default:
                Issue.record("Invalid task kind")
                return
            }
        }
        var fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        var expected = try JSONDecoder().decode(
            ModelsR4.QuestionnaireResponse.self,
            from: Data(
                contentsOf: try #require(Foundation.Bundle.module.url(forResource: "PHQ9_response_rkof", withExtension: "json"))
            )
        )
        let fix = { (response: inout ModelsR4.QuestionnaireResponse) in
            // we need to null some fields out bc they will never be equal
            response.authored = nil // response date
            response.id = nil
            response.identifier = nil
            response.questionnaire = nil
        }
        fix(&fhirResponse)
        fix(&expected)
        #expect(fhirResponse == expected)
    }
    
    
    @Test
    func responseConversion() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(id: "", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "s0", tasks: [
                    .init(id: "t0", title: "", kind: .numeric(.init(inputMode: .numberPad(.integer))))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["t0"].value.numberValue = 123
        let fhir = try ModelsR4.QuestionnaireResponse(responses)
        let items = try #require(fhir.item)
        #expect(items.count == 1)
        let item = try #require(items.first)
        let answers = try #require(item.answer)
        #expect(answers.count == 1)
        let answer = try #require(answers.first)
        #expect(answer.value == .decimal(123.asFHIRDecimalPrimitive()))
    }
    
    
    @Test(arguments: ["Diet", "PHQ9"])
    func fhirResponsesStructureVsRKoF(filename: String) throws {
        let rkofResultUrl = try #require(Foundation.Bundle.module.url(forResource: "\(filename)_response_rkof", withExtension: "json"))
        let groveResultUrl = try #require(Foundation.Bundle.module.url(forResource: "\(filename)_response_grove", withExtension: "json"))
        var rkofResponse = try JSONDecoder().decode(ModelsR4.QuestionnaireResponse.self, from: Data(contentsOf: rkofResultUrl))
        var groveResponse = try JSONDecoder().decode(ModelsR4.QuestionnaireResponse.self, from: Data(contentsOf: groveResultUrl))
        let fix = { (response: inout ModelsR4.QuestionnaireResponse) in
            // we need to null some fields out bc they will never be equal
            response.authored = nil // response date
            response.id = nil
            response.identifier = nil
        }
        fix(&groveResponse)
        fix(&rkofResponse)
        #expect(rkofResponse == groveResponse)
    }
    
    
    // Reproduces the mismatch between option IDs (stored as bare `code`)
    // and enableWhen coding conditions (stored as `"\(system):\(code)"`).
    @Test("Dependent task is enabled when the triggering choice option is selected")
    func enableWhenCodingConditionEvaluatesCorrectly() throws { // swiftlint:disable:this function_body_length
        let system = "http://example.com/codesystem"
        let code = "LA6568-5"
        // Build a minimal FHIR questionnaire:
        //   item1 – choice question with one coding-based answer option
        //   item2 – boolean question, enabled only when q1 == the coding above
        let fhirQuestionnaire: ModelsR4.Questionnaire = { // swiftlint:disable:this closure_body_length
            let answerOption = QuestionnaireItemAnswerOption(
                value: .coding(Coding(
                    code: code.asFHIRStringPrimitive(),
                    display: "Yes".asFHIRStringPrimitive(),
                    system: system.asFHIRURIPrimitive()
                ))
            )
            let item1 = QuestionnaireItem(
                answerOption: [answerOption],
                linkId: "q1".asFHIRStringPrimitive(),
                text: "Do you like ice cream?".asFHIRStringPrimitive(),
                type: .init(.choice)
            )
            let enableWhen = QuestionnaireItemEnableWhen(
                answer: .coding(Coding(
                    code: code.asFHIRStringPrimitive(),
                    system: system.asFHIRURIPrimitive()
                )),
                operator: .init(.equal),
                question: "q1".asFHIRStringPrimitive()
            )
            let item2 = QuestionnaireItem(
                enableWhen: [enableWhen],
                linkId: "q2".asFHIRStringPrimitive(),
                text: "Follow-up question (should only appear when Yes is selected)".asFHIRStringPrimitive(),
                type: .init(.boolean)
            )
            let group = QuestionnaireItem(
                item: [item1, item2],
                linkId: "section1".asFHIRStringPrimitive(),
                type: .init(.group)
            )
            let questionnaire = ModelsR4.Questionnaire(
                id: "test-questionnaire".asFHIRStringPrimitive(),
                item: [group],
                status: .init(.active)
            )
            return questionnaire
        }()
        
        // Convert to GroveQuestionnaire
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        
        // Retrieve the converted tasks
        let section = try #require(questionnaire.sections.first)
        let q1Task = try #require(section.tasks.first { $0.id == "q1" })
        let q2Task = try #require(section.tasks.first { $0.id == "q2" })
        
        // The converted option id should be the bare code "LA6568-5"
        guard case .choice(let choiceConfig) = q1Task.kind.variant else {
            Issue.record("Expected q1 to be a choice task")
            return
        }
        let optionId = try #require(choiceConfig.options.first?.id)
        #expect(optionId == code, "Option ID should be the bare code '\(code)', got '\(optionId)'")
        
        // Simulate selecting that option in a response
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let responsePath = QuestionnaireResponses.ResponsePath(taskId: q1Task.id)
        responses.responses[responsePath] = .init(
            value: .choice(.init(selectedOptions: [optionId]))
        )
        
        // q2 should now be enabled — this assertion currently FAILS because the
        // enableWhen condition stores ".SCMCOption(id: "http://example.com/codesystem:LA6568-5")"
        // while the selected option ID is just "LA6568-5".
        #expect(
            responses.shouldEnable(task: q2Task),
            """
            q2 should be enabled after selecting option '\(optionId)', \
            but the enableWhen condition uses id '\(system):\(code)' — mismatch!
            """
        )
    }
}
