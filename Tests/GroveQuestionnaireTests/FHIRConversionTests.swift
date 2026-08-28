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
            _ = try GroveQuestionnaire.Questionnaire(input, evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
    }


    /// Every bundled example must survive the round trip, not just be readable.
    ///
    /// A response carries the canonical of the exact questionnaire version it answers, so an
    /// example without a version imports cleanly and then strands the participant at submission.
    @Test
    func everyBundledExampleExports() throws {
        let allR4Inputs = ModelsR4.Questionnaire.exampleQuestionnaires + ModelsR4.Questionnaire.researchQuestionnaires
        for input in allR4Inputs {
            let questionnaire = try GroveQuestionnaire.Questionnaire(input, evaluationInstant: questionnaireResponseTestAuthoredAt)
            _ = try ModelsR4.QuestionnaireResponse(
                QuestionnaireResponses(questionnaire: questionnaire),
                authored: questionnaireResponseTestAuthoredAt,
                authoredTimeZone: questionnaireResponseTestTimeZone
            )
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
        var fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
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
            // Grove enriches beyond the RKoF golden file: completionMode + item.text, and the
            // profile it claims, which the golden file predates.
            response.extension = nil
            response.meta = nil
            func strippingText(_ items: [QuestionnaireResponseItem]) -> [QuestionnaireResponseItem] {
                items.map { item in
                    var item = item
                    item.text = nil
                    item.item = item.item.map(strippingText)
                    return item
                }
            }
            response.item = response.item.map(strippingText)
        }
        fix(&fhirResponse)
        fix(&expected)
        #expect(fhirResponse == expected)
    }
    
    
    @Test
    func responseConversion() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "numeric-answer",
                url: URL(string: "https://example.org/fhir/Questionnaire/numeric-answer"),
                version: "1.0.0",
                title: "",
                explainer: ""
            ),
            sections: [
                .init(id: "s0", tasks: [
                    .init(id: "t0", title: "", kind: .numeric(.init(inputMode: .numberPad(.integer))))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["t0"].value.numberValue = 123
        let fhir = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
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
    
    
    // Coding-based options and enableWhen conditions both use `system|code` tokens,
    // so system-qualified matching stays intact end to end.
    @Test("Dependent task is enabled when the triggering choice option is selected")
    func enableWhenCodingConditionEvaluatesCorrectly() throws {
        let system = "http://example.com/codesystem"
        let code = "LA6568-5"
        // Build a minimal FHIR questionnaire:
        //   item1 – choice question with one coding-based answer option
        //   item2 – boolean question, enabled only when q1 == the coding above
        let fhirQuestionnaire: ModelsR4.Questionnaire = {
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
            var questionnaire = ModelsR4.Questionnaire(
                id: "test-questionnaire".asFHIRStringPrimitive(),
                item: [group],
                status: .init(.active)
            )
            questionnaire.url = "https://example.org/fhir/Questionnaire/enable-when-coding".asFHIRURIPrimitive()
            questionnaire.version = "1.0.0".asFHIRStringPrimitive()
            return questionnaire
        }()
        
        // Convert to GroveQuestionnaire
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, evaluationInstant: questionnaireResponseTestAuthoredAt)
        
        // Retrieve the converted tasks
        let section = try #require(questionnaire.sections.first)
        let q1Task = try #require(section.tasks.first { $0.id == "q1" })
        let q2Task = try #require(section.tasks.first { $0.id == "q2" })
        
        // The converted option id carries the system: "system|code"
        guard case .choice(let choiceConfig) = q1Task.kind.variant else {
            Issue.record("Expected q1 to be a choice task")
            return
        }
        let optionId = try #require(choiceConfig.options.first?.id)
        #expect(optionId == "\(system)|\(code)", "Option ID should be '\(system)|\(code)', got '\(optionId)'")
        
        // Simulate selecting that option in a response
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let responsePath = QuestionnaireResponses.ResponsePath(taskId: q1Task.id)
        responses.responses[responsePath] = .init(
            value: .choice(.init(selectedOptions: [optionId]))
        )
        
        #expect(
            responses.shouldEnable(task: q2Task),
            "q2 should be enabled after selecting option '\(optionId)'"
        )
    }
}
