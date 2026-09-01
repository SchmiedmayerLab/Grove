//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


@Suite
struct FHIRConversionCustomTasksTests {
    @Test
    func simpleCustomTask() throws {
        struct Config: QuestionKindConfig {
            let options: [String]
        }
        struct RankChoicesTask: QuestionKindDefinition, QuestionKindDefinitionWithFHIRSupport {
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }
            
            static func parse(_ item: QuestionnaireItem) throws(GroveQuestionnaire.Questionnaire.ConversionError) -> Config? {
                guard let itemControlExt = item.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl").first,
                      let itemControlCoding = itemControlExt.value?.codeableConceptValue?.coding?.first,
                      itemControlCoding.system == "https://grovealliance.org/fhir/questionnaire/CodeSystem/test-custom-item-control",
                      itemControlCoding.code == "rank-options" else {
                    return nil
                }
                let options = (item.answerOption ?? []).compactMap { option in
                    switch option.value {
                    case .coding(let coding):
                        coding.display?.value?.string
                    default:
                        nil
                    }
                }
                return .init(options: options)
            }
            
            static func toFHIR(
                _ response: QuestionnaireResponses.Response,
                for task: GroveQuestionnaire.Questionnaire.Task
            ) throws -> [QuestionnaireResponseItemAnswer] {
                throw NSError(domain: "edu.stanford.Questionnaire", code: 0)
            }
        }
        let input = Data(
            """
            {
              "title": "Test",
              "resourceType": "Questionnaire",
              "id": "org.grovealliance.Grove.Questionnaire.test",
              "url": "https://example.org/fhir/Questionnaire/test-custom-task",
              "version": "1.0.0",
              "language": "en-US",
              "status": "draft",
              "meta": {
                "profile": [
                  "https://grovealliance.org/fhir/questionnaire/StructureDefinition/grove-questionnaire"
                ],
                "tag": [
                  {
                    "system": "urn:ietf:bcp:47",
                    "code": "en-US",
                    "display": "English"
                  }
                ]
              },
              "useContext": [
                {
                  "code": {
                    "system": "http://hl7.org/fhir/ValueSet/usage-context-type",
                    "code": "focus",
                    "display": "Clinical Focus"
                  },
                  "valueCodeableConcept": {
                    "coding": [
                      {
                        "system": "urn:oid:2.16.578.1.12.4.1.1.8655",
                        "display": "Test"
                      }
                    ]
                  }
                }
              ],
              "contact": [
                {}
              ],
              "subjectType": [
                "Patient"
              ],
              "item": [
                {
                  "linkId": "t0",
                  "type": "boolean",
                  "text": "Question 1",
                  "answerOption": [
                    {
                      "valueCoding": {
                        "id": "1eb9d6b5-dd4c-4293-e71e-cecba2d6bf38",
                        "code": "strawberry",
                        "system": "urn:uuid:a360d428-8b3a-416d-c0a2-31350e7a9fd3",
                        "display": "Strawberry"
                      }
                    },
                    {
                      "valueCoding": {
                        "id": "938d681e-d783-4115-9fa8-7b076cd45a84",
                        "code": "mango",
                        "system": "urn:uuid:a360d428-8b3a-416d-c0a2-31350e7a9fd3",
                        "display": "Mango"
                      }
                    },
                    {
                      "valueCoding": {
                        "id": "32438435-394e-4126-8af1-b9063d185443",
                        "code": "chocolate",
                        "system": "urn:uuid:a360d428-8b3a-416d-c0a2-31350e7a9fd3",
                        "display": "Chocolate"
                      }
                    }
                  ],
                  "extension": [
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                      "valueCodeableConcept": {
                        "coding": [
                          {
                            "system": "https://grovealliance.org/fhir/questionnaire/CodeSystem/test-custom-item-control",
                            "code": "rank-options"
                          }
                        ]
                      }
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(
            try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: input),
            evaluationInstant: questionnaireResponseTestAuthoredAt,
            using: .init(
                extraQuestionKinds: [RankChoicesTask.self]
            )
        )
        #expect(questionnaire.sections.count == 1)
        #expect(questionnaire.sections[0].tasks.count == 1)
        let task = try #require(questionnaire.sections.first?.tasks.first)
        #expect(task == .init(
            id: "t0",
            title: "Question 1",
            kind: .custom(RankChoicesTask.self, config: .init(options: ["Strawberry", "Mango", "Chocolate"])),
            isOptional: true // no `required` in the fixture; FHIR defaults it to false
        ))
        #expect(task.id == "t0")
        #expect(task.title == "Question 1")
        switch task.kind.variant {
        case let .custom(questionKind, config):
            #expect(ObjectIdentifier(questionKind) == ObjectIdentifier(RankChoicesTask.self))
            let config = try #require(config as? Config)
            #expect(config == Config(options: ["Strawberry", "Mango", "Chocolate"]))
        default:
            Issue.record()
        }
        #expect(task.kind == .custom(RankChoicesTask.self, config: .init(options: ["Strawberry", "Mango", "Chocolate"])))
        #expect(task.kind.variant == .custom(
            questionKind: RankChoicesTask.self,
            config: RankChoicesTask.Config(options: ["Strawberry", "Mango", "Chocolate"])
        ))
    }
}
