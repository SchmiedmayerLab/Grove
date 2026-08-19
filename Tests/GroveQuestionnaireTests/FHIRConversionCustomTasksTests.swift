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
import SwiftUI
import Testing


@Suite
struct FHIRConversionCustomTasksTests {
    @Test
    func simpleCustomTask() throws {
        struct Config: QuestionKindConfig {
            let options: [String]
        }
        struct RankChoicesTask: QuestionKindDefinition, QuestionKindDefinitionWithFHIRSupport {
            static func makeView(
                for task: GroveQuestionnaire.Questionnaire.Task,
                using config: Config,
                response: Binding<QuestionnaireResponses.Response>
            ) -> some View {
                EmptyView()
            }
            
            static func validate(
                response: QuestionnaireResponses.Response,
                for config: Config
            ) -> QuestionnaireResponses.ResponseValidationResult {
                .ok
            }
            
            static func parse(_ item: QuestionnaireItem) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> Config? {
                guard let itemControlExt = item.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl").first,
                      let itemControlCoding = itemControlExt.value?.codeableConceptValue?.coding?.first,
                      itemControlCoding.system == "http://spezi.stanford.edu/fhir/CodeSystem/custom-task/item-control",
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
              "language": "en-US",
              "status": "draft",
              "meta": {
                "profile": [
                  "http://spezi.health/fhir/StructureDefinition/sdf-Questionnaire"
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
                            "system": "http://spezi.stanford.edu/fhir/CodeSystem/custom-task/item-control",
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
    
    
    @Test
    func annotationTask() throws {
        let input = Data(
            """
            {
              "title": "Test",
              "resourceType": "Questionnaire",
              "id": "org.grovealliance.Grove.Questionnaire.test",
              "language": "en-US",
              "status": "draft",
              "meta": {
                "profile": [
                  "http://spezi.health/fhir/StructureDefinition/sdf-Questionnaire"
                ],
                "tag": [
                  {
                    "system": "urn:ietf:bcp:47",
                    "code": "en-US",
                    "display": "English"
                  }
                ]
              },
              "item": [
                {
                  "linkId": "pain-leg",
                  "text": "In each leg, where do you feel pain?",
                  "type": "attachment",
                  "extension": [
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                      "valueCodeableConcept": {
                        "coding": [
                          {
                            "system": "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control",
                            "code": "annotate-image"
                          }
                        ]
                      }
                    },
                    {
                      "url": "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control/annotate-image/input-image",
                      "valueString": "bodymap.png"
                    },
                    {
                      "url": "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control/annotate-image/region",
                      "extension": [
                        {
                          "url": "label",
                          "valueString": "Pain"
                        },
                        {
                          "url": "color",
                          "valueString": "red"
                        }
                      ]
                    },
                    {
                      "url": "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control/annotate-image/region",
                      "extension": [
                        {
                          "url": "label",
                          "valueString": "Stiffness"
                        },
                        {
                          "url": "color",
                          "valueString": "blue"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(
            try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: input)
        )
        #expect(questionnaire.sections.count == 1)
        #expect(questionnaire.sections[0].tasks.count == 1)
        let task = try #require(questionnaire.sections.first?.tasks.first)
        #expect(task == .init(
            id: "pain-leg",
            title: "In each leg, where do you feel pain?",
            kind: .annotateImage(AnnotateImageConfig(
                inputImage: .namedInMainBundle(filename: "bodymap.png"),
                regions: [
                    .init(name: "Pain", color: .red),
                    .init(name: "Stiffness", color: .blue)
                ]
            )),
            isOptional: true // no `required` in the fixture; FHIR defaults it to false
        ))
    }


    /// The implementation guide's published example, byte for byte.
    ///
    /// The renderer and the guide have to agree on the exact identifiers, datatypes and
    /// carrier extensions, and only the published bytes can prove that they do.
    @Test
    func publishedGuideExampleParses() throws {
        let input = Data(#"""
            {
              "resourceType": "Questionnaire",
              "id": "GroveQuestionnaireExample",
              "status": "active",
              "name": "GroveExampleQuestionnaire",
              "title": "Grove Example Questionnaire",
              "url": "https://grovealliance.org/fhir/core/Questionnaire/GroveQuestionnaireExample",
              "item": [
                {
                  "linkId": "email",
                  "type": "string",
                  "text": "What is your email address?",
                  "extension": [
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/targetConstraint",
                      "extension": [
                        {
                          "url": "key",
                          "valueId": "email-format"
                        },
                        {
                          "url": "severity",
                          "valueCode": "error"
                        },
                        {
                          "url": "expression",
                          "valueExpression": {
                            "language": "text/fhirpath",
                            "expression": "$this.matches('^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,}$')"
                          }
                        },
                        {
                          "url": "human",
                          "valueString": "Please enter a valid email address."
                        }
                      ]
                    },
                    {
                      "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard",
                      "valueCoding": {
                        "system": "http://hl7.org/fhir/uv/sdc/CodeSystem/keyboardType",
                        "code": "email"
                      }
                    },
                    {
                      "url": "https://grovealliance.org/fhir/core/StructureDefinition/grove-autocomplete",
                      "valueCode": "email"
                    },
                    {
                      "url": "https://grovealliance.org/fhir/core/StructureDefinition/grove-autocapitalize",
                      "valueCode": "none"
                    }
                  ]
                },
                {
                  "linkId": "pain-location",
                  "type": "attachment",
                  "text": "Mark where it hurts.",
                  "extension": [
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                      "valueCodeableConcept": {
                        "coding": [
                          {
                            "system": "https://grovealliance.org/fhir/core/CodeSystem/grove-questionnaire-item-control",
                            "code": "annotate-image"
                          }
                        ]
                      }
                    },
                    {
                      "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia",
                      "valueAttachment": {
                        "contentType": "image/png",
                        "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
                        "title": "Body outline"
                      }
                    },
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/mimeType",
                      "valueCode": "image/png"
                    },
                    {
                      "url": "http://hl7.org/fhir/StructureDefinition/maxSize",
                      "valueDecimal": 5242880
                    },
                    {
                      "url": "https://grovealliance.org/fhir/core/StructureDefinition/grove-annotate-image-region",
                      "extension": [
                        {
                          "url": "label",
                          "valueString": "Left shoulder"
                        },
                        {
                          "url": "code",
                          "valueCoding": {
                            "code": "16982005",
                            "system": "http://snomed.info/sct",
                            "display": "Shoulder region structure"
                          }
                        },
                        {
                          "url": "color",
                          "valueCode": "red"
                        }
                      ]
                    },
                    {
                      "url": "https://grovealliance.org/fhir/core/StructureDefinition/grove-annotate-image-region",
                      "extension": [
                        {
                          "url": "label",
                          "valueString": "Right shoulder"
                        },
                        {
                          "url": "color",
                          "valueCode": "blue"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#.utf8)
        let questionnaire = try GroveQuestionnaire.Questionnaire(
            try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: input)
        )
        let tasks = questionnaire.sections.flatMap(\.tasks)
        // The annotate-image item resolves against the identifiers the guide publishes,
        // taking its base image from the SDC itemMedia attachment.
        let painLocation = try #require(tasks.first { $0.id == "pain-location" })
        guard case .custom(_, let config) = painLocation.kind.variant,
              let config = config as? AnnotateImageConfig else {
            Issue.record("Expected the annotate-image kind, got \(painLocation.kind.variant)")
            return
        }
        guard case .inlineData(let data) = config.inputImage else {
            Issue.record("Expected the base image to come from itemMedia, got \(config.inputImage)")
            return
        }
        #expect(!data.isEmpty)
        #expect(config.regions == [.init(name: "Left shoulder", color: .red), .init(name: "Right shoulder", color: .blue)])
        // The base image is not additionally rendered as decoration alongside the canvas.
        #expect(painLocation.media == nil)

        let email = try #require(tasks.first { $0.id == "email" })
        guard case .freeText(let freeText) = email.kind.variant else {
            Issue.record("Expected a free-text task")
            return
        }
        #expect(freeText.keyboard == .email)
        #expect(email.constraints.count == 1)
        #expect(email.constraints.first?.key == "email-format")

        // The guide's flagship validation rule accepts an address and rejects a non-address.
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["email"] = .init(value: .string("ada@example.org"))
        #expect(responses.validateResponse(for: email).isOk)
        responses.responses["email"] = .init(value: .string("not-an-address"))
        #expect(responses.validateResponse(for: email).isInvalid)
        #expect(responses.expressionFailures.isEmpty)
    }
}
