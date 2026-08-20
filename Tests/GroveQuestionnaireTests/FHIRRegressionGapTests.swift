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
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


/// Pins load-bearing behaviors the other suites did not cover: the `exists`
/// operator, mutually exclusive enable mechanisms, slider preconditions,
/// sibling-group response assembly, draft edge cases, and answer-type details.
@Suite
struct FHIRRegressionGapTests {
    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/regression-gaps".asFHIRURIPrimitive()
        questionnaire.version = "1.0.0".asFHIRStringPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func booleanItem(_ linkId: String) -> ModelsR4.QuestionnaireItem {
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = linkId.asFHIRStringPrimitive()
        return item
    }

    // MARK: enableWhen `exists`

    @Test
    func existsOperatorHonorsPolarity() throws {
        func exists(_ question: String, _ answer: Bool) -> QuestionnaireItemEnableWhen {
            QuestionnaireItemEnableWhen(
                answer: .boolean(FHIRPrimitive(FHIRBool(answer))),
                operator: FHIRPrimitive(QuestionnaireItemOperator.exists),
                question: question.asFHIRStringPrimitive()
            )
        }
        var whenAnswered = booleanItem("when-answered")
        whenAnswered.enableWhen = [exists("source", true)]
        var whenUnanswered = booleanItem("when-unanswered")
        whenUnanswered.enableWhen = [exists("source", false)]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("source"), whenAnswered, whenUnanswered
        ]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let tasks = questionnaire.sections.flatMap(\.tasks)
        let answered = try #require(tasks.first { $0.id == "when-answered" })
        let unanswered = try #require(tasks.first { $0.id == "when-unanswered" })
        #expect(!responses.shouldEnable(task: answered))
        #expect(responses.shouldEnable(task: unanswered))
        responses.responses["source"] = .init(value: .bool(false))
        #expect(responses.shouldEnable(task: answered))
        #expect(!responses.shouldEnable(task: unanswered))
    }

    // MARK: enableWhen + enableWhenExpression are mutually exclusive

    @Test
    func combinedEnableMechanismsAreRejected() throws {
        var item = booleanItem("q2")
        item.enableWhen = [
            QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(true))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: "q1".asFHIRStringPrimitive()
        )
        ]
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
            value: .expression(ModelsR4.Expression(
                expression: "true".asFHIRStringPrimitive(),
                language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
            ))
        )
        ]
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [booleanItem("q1"), item]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
    }

    // MARK: Slider preconditions

    @Test
    func sliderRendersOnlyWithStepAndDegradesWithout() throws {
        func integerItem(_ linkId: String, extensions: [Extension]) -> ModelsR4.QuestionnaireItem {
            var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.integer))
            item.text = linkId.asFHIRStringPrimitive()
            item.extension = extensions
            return item
        }
        let control = Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                code: "slider".asFHIRStringPrimitive(),
                system: "http://hl7.org/fhir/questionnaire-item-control".asFHIRURIPrimitive()
            )
            ]))
        )
        let step = Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-sliderStepValue",
            value: .integer(FHIRPrimitive(FHIRInteger(1)))
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            integerItem("with-step", extensions: [control, step]),
            integerItem("without-step", extensions: [control])
        ]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let tasks = questionnaire.sections.flatMap(\.tasks)
        guard case .numeric(let withStep) = try #require(tasks.first { $0.id == "with-step" }).kind.variant,
              case .numeric(let withoutStep) = try #require(tasks.first { $0.id == "without-step" }).kind.variant else {
            Issue.record("Expected numeric tasks")
            return
        }
        #expect(withStep.inputMode == .slider(stepValue: 1))
        #expect(withoutStep.inputMode == .numberPad(.integer))
    }

    // MARK: Sibling groups in the response

    @Test
    func siblingNestedGroupsReassembleSeparately() throws {
        func group(_ linkId: String, item: ModelsR4.QuestionnaireItem) -> ModelsR4.QuestionnaireItem {
            var groupItem = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.group))
            groupItem.item = [item]
            return groupItem
        }
        var top = ModelsR4.QuestionnaireItem(linkId: "top".asFHIRStringPrimitive(), type: .init(.group))
        top.item = [group("left", item: booleanItem("q1")), group("right", item: booleanItem("q2"))]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [top]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["q1"] = .init(value: .bool(true))
        responses.responses["q2"] = .init(value: .bool(false))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
        let topItem = try #require(fhirResponse.item?.first { $0.linkId.value?.string == "top" })
        #expect(topItem.item?.map { $0.linkId.value?.string } == ["left", "right"])
        #expect(topItem.item?.first?.item?.first?.linkId.value?.string == "q1")
        #expect(topItem.item?.last?.item?.first?.linkId.value?.string == "q2")
    }

    // MARK: Draft edge cases

    @Test
    func draftPreservesNestedFollowUpResponses() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(id: "nested-draft", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "s1", tasks: [
                    .init(id: "pick", title: "Pick", kind: .choice(.init(
                        options: [.init(id: "a", title: "A")],
                        allowsMultipleSelection: false,
                        followUpTasks: [.init(id: "why", title: "Why?", kind: .freeText(.init()))]
                    )))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["pick"] = .init(value: .choice(.init(selectedOptions: ["a"])))
        responses.responses["pick"].nestedResponses[.choiceOption("a")] = {
            var nested = QuestionnaireResponses.Responses()
            nested["why"] = .init(value: .string("because"))
            return nested
        }()
        let resumed = try QuestionnaireResponses(questionnaire: questionnaire, resuming: try responses.draft())
        let nested = resumed.responses["pick"].nestedResponses[.choiceOption("a")]
        #expect(nested?["why"].value == .string("because"))
    }

    @Test
    func draftRefusesDifferentQuestionnaire() throws {
        func plainQuestionnaire(_ id: String) -> GroveQuestionnaire.Questionnaire {
            .init(
                metadata: .init(id: id, url: nil, title: "", explainer: ""),
                sections: [.init(id: "s1", tasks: [.init(id: "q", title: "Q", kind: .boolean)])]
            )
        }
        let responses = QuestionnaireResponses(questionnaire: plainQuestionnaire("original"))
        responses.responses["q"] = .init(value: .bool(true))
        let draft = try responses.draft()
        #expect(throws: QuestionnaireResponses.DraftError.self) {
            try QuestionnaireResponses(questionnaire: plainQuestionnaire("different"), resuming: draft)
        }
    }

    // MARK: Answer-type details

    @Test
    func decimalItemDoesNotChangeItsAnswerTypeBecauseOfAUnitHint() throws {
        var decimal = ModelsR4.QuestionnaireItem(linkId: "weight".asFHIRStringPrimitive(), type: .init(.decimal))
        decimal.text = "weight".asFHIRStringPrimitive()
        decimal.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unit",
            value: .coding(Coding(
                code: "kg".asFHIRStringPrimitive(),
                display: "kg".asFHIRStringPrimitive(),
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive()
            ))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [decimal]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(72.5))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
        guard case let .decimal(value)? = fhirResponse.item?.first?.answer?.first?.value else {
            Issue.record("Expected valueDecimal for a decimal Questionnaire item")
            return
        }
        #expect(value.value?.decimal == 72.5)
    }

    @Test
    func integerAnswerOptionsRoundTrip() throws {
        var choice = ModelsR4.QuestionnaireItem(linkId: "rating".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "rating".asFHIRStringPrimitive()
        choice.answerOption = [1, 2, 3].map {
            QuestionnaireItemAnswerOption(value: .integer(FHIRPrimitive(FHIRInteger($0))))
        }
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .choice(let config) = task.kind.variant else {
            Issue.record("Expected a choice task")
            return
        }
        #expect(config.options.map(\.id) == ["integer|1", "integer|2", "integer|3"])
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["rating"] = .init(value: .choice(.init(selectedOptions: ["integer|3"])))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
        #expect(fhirResponse.item?.first?.answer?.first?.value == .integer(FHIRPrimitive(FHIRInteger(3))))
    }

    @Test
    func shortAndLongTextItemsKeepTheirTypeAcrossARoundTrip() throws {
        func textItem(_ linkId: String, _ type: QuestionnaireItemType) -> ModelsR4.QuestionnaireItem {
            var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(type))
            item.text = linkId.asFHIRStringPrimitive()
            return item
        }
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            textItem("short", .string), textItem("long", .text), textItem("link", .url)
        ]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let tasks = questionnaire.sections.flatMap(\.tasks)
        func freeTextConfig(_ linkId: String) -> GroveQuestionnaire.Questionnaire.Task.Kind.FreeTextConfig? {
            guard case .freeText(let config)? = tasks.first(where: { $0.id == linkId })?.kind.variant else {
                return nil
            }
            return config
        }
        #expect(try #require(freeTextConfig("short")).isMultiline == false)
        #expect(try #require(freeTextConfig("long")).isMultiline == true)
        #expect(try #require(freeTextConfig("link")).isMultiline == false)

        // A `string` used to come back as a `text`, which turned every short answer multi-line.
        let exported = try ModelsR4.Questionnaire(questionnaire)
        func type(_ linkId: String) -> QuestionnaireItemType? {
            exported.item?.first { $0.linkId.value?.string == linkId }?.type.value
        }
        #expect(type("short") == .string)
        #expect(type("long") == .text)
        #expect(type("link") == .url)
    }

    // MARK: Corpus spot check

    @Test
    func phq9ConvertsToTheExpectedStructure() throws {
        let questionnaire = try GroveQuestionnaire.Questionnaire(ModelsR4.Questionnaire.phq9, evaluationInstant: questionnaireResponseTestAuthoredAt)
        let tasks = questionnaire.sections.flatMap(\.tasks)
        let choiceTasks = tasks.filter {
            if case .choice = $0.kind.variant { true } else { false }
        }
        #expect(choiceTasks.count == 9, "PHQ-9 has nine scored questions")
        for task in choiceTasks {
            guard case .choice(let config) = task.kind.variant else {
                continue
            }
            #expect(config.options.count == 4, "each PHQ-9 question offers four frequency options (\(task.id))")
        }
    }
}
