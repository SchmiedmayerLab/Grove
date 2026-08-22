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


/// Covers the correctness fixes layered on top of the conformance rework:
/// hidden items, modifier extensions, tree-wide que-2, option exclusivity and
/// weights, quantity conditions, ValueSet includes, and input-time validation.
@Suite
struct FHIRFoundationFixesTests {
    // MARK: Helpers

    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/foundation".asFHIRURIPrimitive()
        questionnaire.version = "1.0.0".asFHIRStringPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func booleanItem(_ linkId: String, required: Bool = false) -> ModelsR4.QuestionnaireItem {
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = linkId.asFHIRStringPrimitive()
        if required {
            item.required = FHIRPrimitive(FHIRBool(true))
        }
        return item
    }

    // MARK: questionnaire-hidden

    @Test
    func hiddenItemIsParsedAndNeverBlocksCompletion() throws {
        var hidden = booleanItem("carrier", required: true)
        hidden.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden",
            value: .boolean(FHIRPrimitive(FHIRBool(true)))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [hidden, booleanItem("visible")]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let tasks = questionnaire.sections.flatMap(\.tasks)
        let carrier = try #require(tasks.first { $0.id == "carrier" })
        #expect(carrier.isHidden)
        #expect(tasks.first { $0.id == "visible" }?.isHidden == false)
        // Required + hidden + unanswered must not block completion.
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(!responses.isMissingResponse(for: carrier))
        let section = try #require(questionnaire.sections.first)
        #expect(responses.firstTaskPreventingCompletion(of: section)?.id != "carrier")
    }

    // MARK: modifierExtension guard

    @Test
    func unknownModifierExtensionIsRejected() throws {
        var item = booleanItem("q1")
        item.modifierExtension = [
            Extension(
            url: "https://example.org/fhir/StructureDefinition/changes-meaning",
            value: .boolean(FHIRPrimitive(FHIRBool(true)))
        )
        ]
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
    }

    // MARK: que-2 covers group linkIds

    @Test
    func duplicateGroupLinkIdsThrow() throws {
        var group1 = ModelsR4.QuestionnaireItem(linkId: "grp".asFHIRStringPrimitive(), type: .init(.group))
        group1.item = [booleanItem("q1")]
        var group2 = ModelsR4.QuestionnaireItem(linkId: "outer".asFHIRStringPrimitive(), type: .init(.group))
        var nested = ModelsR4.QuestionnaireItem(linkId: "grp".asFHIRStringPrimitive(), type: .init(.group))
        nested.item = [booleanItem("q2")]
        group2.item = [nested]
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [group1, group2]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
    }

    @Test
    func groupLinkIdCollidingWithQuestionThrows() throws {
        var group = ModelsR4.QuestionnaireItem(linkId: "shared".asFHIRStringPrimitive(), type: .init(.group))
        group.item = [booleanItem("q1")]
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [group, booleanItem("shared")]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
    }

    // MARK: answerValueSet reads every include

    @Test
    func allValueSetIncludesContributeOptions() throws {
        var include1 = ValueSetComposeInclude(system: "https://example.org/system-a".asFHIRURIPrimitive())
        include1.concept = [.init(code: "a1".asFHIRStringPrimitive(), display: "A1".asFHIRStringPrimitive())]
        var include2 = ValueSetComposeInclude(system: "https://example.org/system-b".asFHIRURIPrimitive())
        include2.concept = [.init(code: "b1".asFHIRStringPrimitive(), display: "B1".asFHIRStringPrimitive())]
        var valueSet = ValueSet(status: FHIRPrimitive(PublicationStatus.active))
        valueSet.id = "vs1".asFHIRStringPrimitive()
        valueSet.compose = ValueSetCompose(include: [include1, include2])

        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick".asFHIRStringPrimitive()
        choice.answerValueSet = "#vs1".asFHIRCanonicalPrimitive()
        var fhirQuestionnaire = makeQuestionnaire(items: [choice])
        fhirQuestionnaire.contained = [ResourceProxy(with: valueSet)]

        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, evaluationInstant: questionnaireResponseTestAuthoredAt)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .choice(let config) = task.kind.variant else {
            Issue.record("Expected a choice task")
            return
        }
        #expect(config.options.map(\.id) == ["https://example.org/system-a|a1", "https://example.org/system-b|b1"])
    }

    // MARK: optionExclusive

    @Test
    func exclusiveOptionClearsOtherSelections() throws {
        func option(_ code: String, exclusive: Bool = false) -> QuestionnaireItemAnswerOption {
            var answerOption = QuestionnaireItemAnswerOption(value: .coding(Coding(
                code: code.asFHIRStringPrimitive(),
                display: code.asFHIRStringPrimitive(),
                system: "https://example.org/opts".asFHIRURIPrimitive()
            )))
            if exclusive {
                answerOption.extension = [
                    Extension(
                    url: "http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive",
                    value: .boolean(FHIRPrimitive(FHIRBool(true)))
                )
                ]
            }
            return answerOption
        }
        var choice = ModelsR4.QuestionnaireItem(linkId: "symptoms".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "symptoms".asFHIRStringPrimitive()
        choice.repeats = FHIRPrimitive(FHIRBool(true))
        choice.answerOption = [option("cough"), option("fever"), option("none", exclusive: true)]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .choice(let config) = task.kind.variant else {
            Issue.record("Expected a choice task")
            return
        }
        #expect(config.options.first { $0.id.hasSuffix("|none") }?.isExclusive == true)

        var response = QuestionnaireResponses.ChoiceResponse(selectedOptions: [])
        response.select("https://example.org/opts|cough", in: config)
        response.select("https://example.org/opts|fever", in: config)
        #expect(response.selectedOptions.count == 2)
        // Selecting the exclusive option clears the rest.
        response.select("https://example.org/opts|none", in: config)
        #expect(response.selectedOptions == ["https://example.org/opts|none"])
        // Selecting a regular option afterwards clears the exclusive one.
        response.select("https://example.org/opts|cough", in: config)
        #expect(response.selectedOptions == ["https://example.org/opts|cough"])
    }

    // MARK: itemWeight

    @Test
    func optionWeightsAreParsedAndEmittedOnAnswers() throws {
        func weighted(_ code: String, _ weight: Double, url: String) -> QuestionnaireItemAnswerOption {
            var coding = Coding(
                code: code.asFHIRStringPrimitive(),
                display: code.asFHIRStringPrimitive(),
                system: "https://example.org/scale".asFHIRURIPrimitive()
            )
            coding.extension = [Extension(url: url.asFHIRURIPrimitive() ?? "x", value: .decimal(FHIRPrimitive(FHIRDecimal(Decimal(weight)))))]
            return QuestionnaireItemAnswerOption(value: .coding(coding))
        }
        var choice = ModelsR4.QuestionnaireItem(linkId: "mood".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "mood".asFHIRStringPrimitive()
        choice.answerOption = [
            weighted("not-at-all", 0, url: "http://hl7.org/fhir/StructureDefinition/itemWeight"),
            weighted("nearly-every-day", 3, url: "http://hl7.org/fhir/StructureDefinition/itemWeight")
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .choice(let config) = task.kind.variant else {
            Issue.record("Expected a choice task")
            return
        }
        #expect(config.options[0].weight == 0)
        #expect(config.options[1].weight == 3)

        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["mood"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/scale|nearly-every-day"])))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
        guard case let .coding(coding) = fhirResponse.item?.first?.item?.first?.answer?.first?.value ?? fhirResponse.item?.first?.answer?.first?.value else {
            Issue.record("Expected a coding answer")
            return
        }
        let weightExt = coding.extensions(for: "http://hl7.org/fhir/StructureDefinition/itemWeight").first
        guard case let .decimal(emitted) = weightExt?.value else {
            Issue.record("Expected an emitted itemWeight extension")
            return
        }
        #expect(emitted.value?.decimal == 3)
    }

    // MARK: enableWhen answerQuantity

    @Test
    func quantityConditionComparesInMatchingUnit() throws {
        var weight = ModelsR4.QuestionnaireItem(linkId: "weight".asFHIRStringPrimitive(), type: .init(.quantity))
        weight.text = "weight".asFHIRStringPrimitive()
        weight.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unit",
            value: .coding(Coding(
                code: "kg".asFHIRStringPrimitive(),
                display: "kg".asFHIRStringPrimitive(),
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive()
            ))
        )
        ]
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .quantity(Quantity(
                code: "kg".asFHIRStringPrimitive(),
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                unit: "kg".asFHIRStringPrimitive(),
                value: FHIRPrimitive(FHIRDecimal(100))
            )),
            operator: FHIRPrimitive(QuestionnaireItemOperator.greaterThan),
            question: "weight".asFHIRStringPrimitive()
        )
        var followUp = booleanItem("follow-up")
        followUp.enableWhen = [enableWhen]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [weight, followUp]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let target = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "follow-up" })
        #expect(!responses.shouldEnable(task: target))
        responses.responses["weight"] = .init(value: .number(120))
        #expect(responses.shouldEnable(task: target))
        responses.responses["weight"] = .init(value: .number(80))
        #expect(!responses.shouldEnable(task: target))
    }

    // MARK: input-time URL validation

    @Test
    func urlInputIsValidatedBeforeSubmission() throws {
        var url = ModelsR4.QuestionnaireItem(linkId: "website".asFHIRStringPrimitive(), type: .init(.url))
        url.text = "website".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [url]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["website"] = .init(value: .string("not a url"))
        #expect(responses.validateResponse(for: task).isInvalid)
        responses.responses["website"] = .init(value: .string("https://grovealliance.org"))
        #expect(responses.validateResponse(for: task).isOk)
    }
}
