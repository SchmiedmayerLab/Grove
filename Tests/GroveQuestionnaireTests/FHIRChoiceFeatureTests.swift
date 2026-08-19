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


/// Covers the choice/ValueSet/itemControl features: presentations, orientation,
/// selection bounds, openLabel, optionPrefix, external ValueSets, unit options,
/// and help display items.
@Suite
struct FHIRChoiceFeatureTests {
    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/choice-features".asFHIRURIPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func option(_ code: String) -> QuestionnaireItemAnswerOption {
        QuestionnaireItemAnswerOption(value: .coding(Coding(
            code: code.asFHIRStringPrimitive(),
            display: code.asFHIRStringPrimitive(),
            system: "https://example.org/opts".asFHIRURIPrimitive()
        )))
    }

    private func itemControl(_ code: String) -> Extension {
        Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                code: code.asFHIRStringPrimitive(),
                system: "http://hl7.org/fhir/questionnaire-item-control".asFHIRURIPrimitive()
            )
            ]))
        )
    }

    private func choiceConfig(of questionnaire: GroveQuestionnaire.Questionnaire, taskId: String = "c1") throws -> GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig {
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == taskId })
        guard case .choice(let config) = task.kind.variant else {
            throw NSError(domain: "test", code: 1)
        }
        return config
    }

    // MARK: Presentations & Orientation

    @Test
    func dropDownAndAutocompleteControlsAreParsed() throws {
        var dropDown = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        dropDown.text = "pick".asFHIRStringPrimitive()
        dropDown.answerOption = [option("a"), option("b")]
        dropDown.extension = [itemControl("drop-down")]
        var autocomplete = ModelsR4.QuestionnaireItem(linkId: "c2".asFHIRStringPrimitive(), type: .init(.choice))
        autocomplete.text = "search".asFHIRStringPrimitive()
        autocomplete.answerOption = [option("x")]
        autocomplete.extension = [itemControl("autocomplete")]

        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [dropDown, autocomplete]))
        #expect(try choiceConfig(of: questionnaire, taskId: "c1").presentation == .dropDown)
        #expect(try choiceConfig(of: questionnaire, taskId: "c2").presentation == .autocomplete)
    }

    @Test
    func choiceOrientationIsParsed() throws {
        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "likert".asFHIRStringPrimitive()
        choice.answerOption = [option("1"), option("2")]
        choice.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-choiceOrientation",
            value: .code(FHIRPrimitive(ModelsR4.FHIRString("horizontal")))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        #expect(try choiceConfig(of: questionnaire).orientation == .horizontal)
    }

    // MARK: Selection Bounds

    @Test
    func selectionCountBoundsAreEnforced() throws {
        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick up to two".asFHIRStringPrimitive()
        choice.repeats = FHIRPrimitive(FHIRBool(true))
        choice.answerOption = [option("a"), option("b"), option("c")]
        choice.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs",
            value: .integer(FHIRPrimitive(FHIRInteger(2)))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        #expect(try choiceConfig(of: questionnaire).maxSelections == 2)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        responses.responses["c1"] = .init(value: .choice(.init(selectedOptions: [
            "https://example.org/opts|a", "https://example.org/opts|b", "https://example.org/opts|c"
        ])))
        #expect(responses.validateResponse(for: task).isInvalid)
        responses.responses["c1"] = .init(value: .choice(.init(selectedOptions: [
            "https://example.org/opts|a", "https://example.org/opts|b"
        ])))
        #expect(responses.validateResponse(for: task).isOk)
    }

    // MARK: openLabel & optionPrefix

    @Test
    func openLabelAndOptionPrefixAreParsed() throws {
        var openOption = option("listed")
        openOption.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix",
            value: .string(FHIRPrimitive(ModelsR4.FHIRString("A.")))
        )
        ]
        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.openChoice))
        choice.text = "pick".asFHIRStringPrimitive()
        choice.answerOption = [openOption]
        choice.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-openLabel",
            value: .string(FHIRPrimitive(ModelsR4.FHIRString("Something else")))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        let config = try choiceConfig(of: questionnaire)
        #expect(config.freeTextOtherOptionLabel == "Something else")
        #expect(config.options.first?.title == "A. listed")
    }

    // MARK: External ValueSets

    @Test
    func externalValueSetResolvesThroughRegistry() throws {
        var expansion = ValueSetExpansion(timestamp: FHIRPrimitive(try DateTime(date: .now)))
        expansion.contains = [
            {
                var entry = ValueSetExpansionContains()
                entry.system = "https://example.org/external".asFHIRURIPrimitive()
                entry.code = "e1".asFHIRStringPrimitive()
                entry.display = "External One".asFHIRStringPrimitive()
                return entry
            }()
        ]
        var externalValueSet = ValueSet(status: FHIRPrimitive(PublicationStatus.active))
        externalValueSet.expansion = expansion
        let valueSet = externalValueSet

        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick".asFHIRStringPrimitive()
        choice.answerValueSet = "https://example.org/fhir/ValueSet/external".asFHIRCanonicalPrimitive()

        let questionnaire = try GroveQuestionnaire.Questionnaire(
            makeQuestionnaire(items: [choice]),
            using: .init(resolveValueSet: { url in
                url.absoluteString == "https://example.org/fhir/ValueSet/external" ? valueSet : nil
            })
        )
        let config = try choiceConfig(of: questionnaire)
        #expect(config.options.map(\.id) == ["https://example.org/external|e1"])
        #expect(config.options.first?.title == "External One")

        // Without a resolver the conversion fails loudly instead of dropping options.
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        }
    }

    // MARK: Unit Options

    @Test
    func unitOptionsAreParsedAndEmittedWithChosenUnit() throws {
        func unitOption(_ code: String, _ display: String) -> Extension {
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption",
                value: .coding(Coding(
                    code: code.asFHIRStringPrimitive(),
                    display: display.asFHIRStringPrimitive(),
                    system: "http://unitsofmeasure.org".asFHIRURIPrimitive()
                ))
            )
        }
        var weight = ModelsR4.QuestionnaireItem(linkId: "weight".asFHIRStringPrimitive(), type: .init(.quantity))
        weight.text = "weight".asFHIRStringPrimitive()
        weight.extension = [unitOption("kg", "kilograms"), unitOption("[lb_av]", "pounds")]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [weight]))
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .numeric(let config) = task.kind.variant else {
            Issue.record("Expected a numeric task")
            return
        }
        #expect(config.unitOptions.map(\.code) == ["kg", "[lb_av]"])

        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .quantity(150, unitCode: "[lb_av]"))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        guard case let .quantity(quantity)? = fhirResponse.item?.first?.answer?.first?.value else {
            Issue.record("Expected a quantity answer")
            return
        }
        #expect(quantity.code?.value?.string == "[lb_av]")
        #expect(quantity.unit?.value?.string == "pounds")
        #expect(quantity.system?.value?.url.absoluteString == "http://unitsofmeasure.org")
    }

    // MARK: Help Display Items

    @Test
    func helpDisplayItemBecomesFooterNotTask() throws {
        var help = ModelsR4.QuestionnaireItem(linkId: "q1-help".asFHIRStringPrimitive(), type: .init(.display))
        help.text = "Count every alcoholic beverage, including beer and wine.".asFHIRStringPrimitive()
        help.extension = [itemControl("help")]
        var question = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.integer))
        question.text = "Drinks per week?".asFHIRStringPrimitive()
        question.item = [help]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [question]))
        let tasks = questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.count == 1, "the help item must not become its own task")
        #expect(tasks.first?.footer.contains("alcoholic beverage") == true)
    }
}
