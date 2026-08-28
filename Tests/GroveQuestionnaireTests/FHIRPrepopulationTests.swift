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
        questionnaire.version = "1.0.0".asFHIRStringPrimitive()
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

        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [boolean, integer]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.responses["consented"].value == .bool(true))
        #expect(responses.responses["count"].value == .number(7))
        // Seeded values flow into the generated response.
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
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
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]), evaluationInstant: questionnaireResponseTestAuthoredAt)
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
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [locked]), evaluationInstant: questionnaireResponseTestAuthoredAt)
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
        #expect(throws: GroveQuestionnaire.Questionnaire.ConversionError.self) {
            try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, evaluationInstant: questionnaireResponseTestAuthoredAt)
        }
        // Inspection tooling can opt out of the gate.
        let converted = try GroveQuestionnaire.Questionnaire(
            fhirQuestionnaire,
            evaluationInstant: questionnaireResponseTestAuthoredAt,
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
        period.end = FHIRPrimitive(try DateTime(date: questionnaireResponseTestAuthoredAt.addingTimeInterval(-86_400)))
        fhirQuestionnaire.effectivePeriod = period
        // Out-of-period instruments still convert (published examples carry ended
        // periods), but the app is told so it can warn or refuse.
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, evaluationInstant: questionnaireResponseTestAuthoredAt)
        #expect(questionnaire.metadata.administrationWarnings.contains { $0.contains("effectivePeriod") })
    }

    @Test
    func relativeDateBoundsUseTheExplicitEvaluationInstant() throws {
        var birthday = ModelsR4.QuestionnaireItem(
            linkId: "birthday".asFHIRStringPrimitive(),
            text: "Birthday".asFHIRStringPrimitive(),
            type: .init(.date)
        )
        birthday.extension = [
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/maxValue",
                value: .string("today() - 18 years".asFHIRStringPrimitive())
            )
        ]
        let source = makeQuestionnaire(items: [birthday])

        func maximum(at instant: Date) throws -> DateComponents {
            let questionnaire = try GroveQuestionnaire.Questionnaire(
                source,
                evaluationInstant: instant
            )
            let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
            guard case .dateTime(let config) = task.kind.variant else {
                Issue.record("Expected a date task")
                return DateComponents()
            }
            return try #require(config.maxValue)
        }

        let firstInstant = Date(timeIntervalSince1970: 1_700_000_000)
        let laterInstant = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try maximum(at: firstInstant)
        let repeated = try maximum(at: firstInstant)
        let later = try maximum(at: laterInstant)
        let calendar = Calendar.current
        let expectedDate = try #require(calendar.date(byAdding: .year, value: -18, to: firstInstant))
        let expected = calendar.dateComponents([.year, .month, .day], from: expectedDate)

        #expect(first.year == expected.year)
        #expect(first.month == expected.month)
        #expect(first.day == expected.day)
        #expect(first == repeated)
        #expect(first != later)
    }

    @Test
    func publisherAndCopyrightAreParsed() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        fhirQuestionnaire.publisher = "Pfizer Inc.".asFHIRStringPrimitive()
        fhirQuestionnaire.copyright = "© Pfizer Inc. All rights reserved.".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, evaluationInstant: questionnaireResponseTestAuthoredAt)
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
            evaluationInstant: questionnaireResponseTestAuthoredAt,
            using: .init(locale: Locale(identifier: "de_DE"))
        )
        #expect(german.sections.flatMap(\.tasks).first?.title == "Wie geht es Ihnen heute?")
        let english = try GroveQuestionnaire.Questionnaire(
            makeQuestionnaire(items: [item]),
            evaluationInstant: questionnaireResponseTestAuthoredAt,
            using: .init(locale: Locale(identifier: "en_US"))
        )
        #expect(english.sections.flatMap(\.tasks).first?.title == "How are you today?")
    }

    // MARK: Response attribution

    @Test
    func responseCarriesAttributionAndItemText() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Do you feel well?".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]), evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["q1"] = .init(value: .bool(true))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            subject: Reference(reference: "Patient/participant-1".asFHIRStringPrimitive()),
            author: Reference(reference: "Device/app-instance".asFHIRStringPrimitive()),
            authored: questionnaireResponseTestAuthoredAt
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
