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


/// Covers answer pre-population (`initial[x]`, `initialSelected`), localization,
/// publication-lifecycle gating, and QuestionnaireResponse attribution.
@Suite
struct FHIRPrepopulationTests {
    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/prepopulation".asFHIRURIPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    // MARK: initial[x]

    @Test
    func initialValuesSeedResponses() throws {
        var boolean = ModelsR4.QuestionnaireItem(linkId: "consented".asFHIRStringPrimitive(), type: .init(.boolean))
        boolean.text = "consented".asFHIRStringPrimitive()
        boolean.initial = [QuestionnaireItemInitial(value: .boolean(FHIRPrimitive(FHIRBool(true))))]
        var integer = ModelsR4.QuestionnaireItem(linkId: "count".asFHIRStringPrimitive(), type: .init(.integer))
        integer.text = "count".asFHIRStringPrimitive()
        integer.initial = [QuestionnaireItemInitial(value: .integer(FHIRPrimitive(FHIRInteger(7))))]

        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [boolean, integer]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.responses["consented"].value == .bool(true))
        #expect(responses.responses["count"].value == .number(7))
        // Seeded values flow into the generated response.
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        #expect(fhirResponse.item?.count == 2)
    }

    @Test
    func initialSelectedPreselectsChoiceOptions() throws {
        func option(_ code: String, selected: Bool = false) -> QuestionnaireItemAnswerOption {
            var answerOption = QuestionnaireItemAnswerOption(value: .coding(Coding(
                code: code.asFHIRStringPrimitive(),
                display: code.asFHIRStringPrimitive(),
                system: "https://example.org/opts".asFHIRURIPrimitive()
            )))
            if selected {
                answerOption.initialSelected = FHIRPrimitive(FHIRBool(true))
            }
            return answerOption
        }
        var choice = ModelsR4.QuestionnaireItem(linkId: "pick".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick".asFHIRStringPrimitive()
        choice.answerOption = [option("a"), option("b", selected: true)]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.responses["pick"].value.choiceValue.selectedOptions == ["https://example.org/opts|b"])
    }

    @Test
    func requiredReadOnlyItemWithInitialCompletes() throws {
        var locked = ModelsR4.QuestionnaireItem(linkId: "locked".asFHIRStringPrimitive(), type: .init(.boolean))
        locked.text = "locked".asFHIRStringPrimitive()
        locked.required = FHIRPrimitive(FHIRBool(true))
        locked.readOnly = FHIRPrimitive(FHIRBool(true))
        locked.initial = [QuestionnaireItemInitial(value: .boolean(FHIRPrimitive(FHIRBool(true))))]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [locked]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let section = try #require(questionnaire.sections.first)
        #expect(responses.isComplete(in: section))
    }

    // MARK: Publication lifecycle

    @Test
    func retiredQuestionnaireIsRefused() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        fhirQuestionnaire.status = FHIRPrimitive(PublicationStatus.retired)
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        }
        // Inspection tooling can opt out of the gate.
        let converted = try GroveQuestionnaire.Questionnaire(
            fhirQuestionnaire,
            using: .init(enforcesPublicationLifecycle: false)
        )
        #expect(converted.metadata.lifecycle == .retired)
    }

    @Test
    func expiredEffectivePeriodSurfacesAWarning() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        var period = Period()
        period.end = FHIRPrimitive(try DateTime(date: Date(timeIntervalSinceNow: -86_400)))
        fhirQuestionnaire.effectivePeriod = period
        // Out-of-period instruments still convert (published examples carry ended
        // periods), but the app is told so it can warn or refuse.
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        #expect(questionnaire.metadata.administrationWarnings.contains { $0.contains("effectivePeriod") })
    }

    @Test
    func publisherAndCopyrightAreParsed() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        fhirQuestionnaire.publisher = "Pfizer Inc.".asFHIRStringPrimitive()
        fhirQuestionnaire.copyright = "© Pfizer Inc. All rights reserved.".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        #expect(questionnaire.metadata.publisher == "Pfizer Inc.")
        #expect(questionnaire.metadata.copyright == "© Pfizer Inc. All rights reserved.")
    }

    // MARK: Localization

    @Test
    func translationExtensionSelectsLocalizedText() throws {
        var text: FHIRPrimitive<ModelsR4.FHIRString> = "How are you today?"
        var translation = Extension(url: "http://hl7.org/fhir/StructureDefinition/translation")
        translation.extension = [
            Extension(url: "lang", value: .code(FHIRPrimitive(ModelsR4.FHIRString("de")))),
            Extension(url: "content", value: .string(FHIRPrimitive(ModelsR4.FHIRString("Wie geht es Ihnen heute?"))))
        ]
        text.extension = [translation]
        var item = ModelsR4.QuestionnaireItem(linkId: "mood".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = text

        let german = try GroveQuestionnaire.Questionnaire(
            makeQuestionnaire(items: [item]),
            using: .init(locale: Locale(identifier: "de_DE"))
        )
        #expect(german.sections.flatMap(\.tasks).first?.title == "Wie geht es Ihnen heute?")
        let english = try GroveQuestionnaire.Questionnaire(
            makeQuestionnaire(items: [item]),
            using: .init(locale: Locale(identifier: "en_US"))
        )
        #expect(english.sections.flatMap(\.tasks).first?.title == "How are you today?")
    }

    // MARK: Response attribution

    @Test
    func responseCarriesAttributionAndItemText() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Do you feel well?".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["q1"] = .init(value: .bool(true))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            subject: Reference(reference: "Patient/participant-1".asFHIRStringPrimitive()),
            author: Reference(reference: "Device/app-instance".asFHIRStringPrimitive())
        )
        #expect(fhirResponse.subject?.reference?.value?.string == "Patient/participant-1")
        #expect(fhirResponse.author?.reference?.value?.string == "Device/app-instance")
        let completionMode = fhirResponse.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-completionMode").first
        guard case let .codeableConcept(concept)? = completionMode?.value else {
            Issue.record("Expected a completionMode extension")
            return
        }
        #expect(concept.coding?.first?.code?.value?.string == "ELECTRONIC")
        #expect(concept.coding?.first?.system?.value?.url.absoluteString == "http://terminology.hl7.org/CodeSystem/v3-ParticipationMode")
        #expect(fhirResponse.item?.first?.text?.value?.string == "Do you feel well?")
    }
}
