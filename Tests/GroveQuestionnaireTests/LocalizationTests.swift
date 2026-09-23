//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveQuestionnaire
import GroveQuestionnaireFHIR
import ModelsR4
import Testing


@Suite
struct LocalizationTests {
    private typealias Text = GroveQuestionnaire.Questionnaire.LocalizedText

    private static let url = URL(string: "https://example.org/fhir/Questionnaire/localized")
    private static let moodSystem = URL(string: "https://example.org/mood")!

    /// A questionnaire written in `en-US`, translated into British English, Spanish and Mexican Spanish.
    private static func questionnaire(language: String? = "en-US") -> GroveQuestionnaire.Questionnaire {
        let translated = { (base: String) in
            Text(base, translations: ["en-GB": "\(base) (GB)", "es": "\(base) (es)", "es-MX": "\(base) (MX)"])
        }
        return GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "localized",
                url: url,
                version: "1.0.0",
                language: language,
                title: translated("Check-In"),
                explainer: translated("How you are doing")
            ),
            sections: [
                .init(
                    id: "section",
                    title: translated("Today"),
                    shortTitle: translated("Now"),
                    tasks: [
                        .init(id: "intro", title: "", kind: .instructional(translated("Please answer"))),
                        .init(
                            id: "mood",
                            title: translated("How do you feel?"),
                            prefix: translated("1."),
                            shortTitle: translated("Mood"),
                            footer: translated("Take your time"),
                            kind: .choice(.init(
                                options: [
                                    .init(
                                        id: "https://example.org/mood|good",
                                        title: translated("Good"),
                                        fhirCoding: .init(system: moodSystem, code: "good")
                                    ),
                                    .init(id: "string|meh", title: .init("meh", translations: ["es": "regular"]), answerValue: .string("meh"))
                                ],
                                hasFreeTextOtherOption: true,
                                freeTextOtherOptionLabel: translated("Something else"),
                                allowsMultipleSelection: false
                            )),
                            constraints: [.init(expression: "true", humanDescription: translated("Pick one"), key: "mood-1")],
                            groupPath: [.init(id: "feelings", title: translated("Feelings"), shortTitle: translated("F"))]
                        ),
                        .init(
                            id: "weight",
                            title: "Weight",
                            kind: .numeric(.init(
                                inputMode: .numberPad(.decimal),
                                unit: translated("kilograms"),
                                unitSystem: URL(string: "http://unitsofmeasure.org"),
                                unitCode: "kg",
                                valueKind: .quantity
                            )),
                            isOptional: true
                        )
                    ],
                    fhirGroupId: "section"
                )
            ]
        )
    }

    @Test("A locale renders in the exact tag, then its primary language, then the base language", arguments: [
        ("en_US", "en-US"),
        ("en_GB", "en-GB"),
        ("en_AU", "en-US"),
        ("es_MX", "es-MX"),
        ("es_US", "es"),
        ("fr_FR", "en-US")
    ])
    func renderingLanguageFollowsTheSelectionRule(locale: String, language: String) {
        #expect(Self.questionnaire().renderingLanguage(for: Locale(identifier: locale)) == language)
    }

    @Test
    func questionnaireOffersItsBaseAndEveryTranslationLanguage() {
        #expect(Self.questionnaire().languages == ["en-US", "en-GB", "es", "es-MX"])
        #expect(Self.questionnaire(language: nil).languages == ["en-GB", "es", "es-MX"])
    }

    @Test
    func textResolvesToItsTranslationOrElseTheBase() {
        let text = Text("Good", translations: ["es": "Bien"])
        #expect(text.resolved(in: "es") == "Bien")
        #expect(text.resolved(in: "ES") == "Bien")
        #expect(text.resolved(in: "es-MX") == "Good")
        #expect(text.resolved(in: "en-US") == "Good")
        #expect(text.resolved(in: nil) == "Good")
        #expect(Text(stringLiteral: "Good") == Text("Good"))
    }

    @Test
    func exportWritesTheBaseLanguageAndEveryTranslation() throws {
        let fhir = try ModelsR4.Questionnaire(Self.questionnaire())
        #expect(fhir.language?.value?.string == "en-US")
        let json = try String(decoding: JSONEncoder().encode(fhir), as: UTF8.self)
        let texts = [
            "Check-In", "How you are doing", "Today", "Now", "Please answer", "How do you feel?", "1.", "Mood", "Take your time",
            "Good", "Something else", "Pick one", "Feelings", "F", "kilograms"
        ]
        for base in texts {
            for suffix in ["(GB)", "(es)", "(MX)"] {
                #expect(json.contains("\"\(base) \(suffix)\""), "\(base) \(suffix)")
            }
        }
        #expect(json.contains("\"regular\""))
    }

    @Test
    func exportRoundTripsEveryLanguage() throws {
        let questionnaire = Self.questionnaire()
        let exported = try ModelsR4.Questionnaire(questionnaire)
        let imported = try GroveQuestionnaire.Questionnaire(exported, clock: questionnaireResponseTestClock)
        #expect(imported.metadata.language == "en-US")
        #expect(imported.languages == questionnaire.languages)
        #expect(try ModelsR4.Questionnaire(imported) == exported)
        let mood = try #require(imported.sections.first?.tasks.first { $0.id == "mood" })
        #expect(mood.title == questionnaire.sections[0].tasks[1].title)
        guard case .choice(let config) = mood.kind.variant else {
            Issue.record("Expected a choice")
            return
        }
        #expect(config.options.map(\.title) == [
            Text("Good", translations: ["en-GB": "Good (GB)", "es": "Good (es)", "es-MX": "Good (MX)"]),
            Text("meh", translations: ["es": "regular"])
        ])
        #expect(config.options.last?.answerValue == .string("meh"))
    }

    @Test
    func exportRequiresTheBaseLanguage() throws {
        #expect(throws: ContractError.missingQuestionnaireLanguage) {
            try ModelsR4.Questionnaire(Self.questionnaire(language: nil))
        }
        let responses = QuestionnaireResponses(questionnaire: Self.questionnaire(language: nil))
        #expect(throws: ContractError.missingQuestionnaireLanguage) {
            try ModelsR4.QuestionnaireResponse(
                responses,
                renderedIn: questionnaireResponseTestLocale,
                authored: questionnaireResponseTestAuthoredAt,
                authoredTimeZone: questionnaireResponseTestTimeZone
            )
        }
    }

    @Test("A text translates neither into the base language nor twice into one language", arguments: [
        ["en-us": "Hi"],
        ["es": "Hola", "ES": "Buenas"]
    ])
    func exportRejectsConflictingTranslations(translations: [String: String]) {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(id: "conflict", url: Self.url, version: "1.0.0", language: "en-US", title: .init("Hello", translations: translations), explainer: ""),
            sections: [.init(id: "section", tasks: [.init(id: "well", title: "Well?", kind: .boolean)])]
        )
        #expect(throws: ContractError.self) {
            try ModelsR4.Questionnaire(questionnaire)
        }
    }

    @Test("A response names its rendering language and carries text only in the base language", arguments: [
        ("en_US", "en-US", true),
        ("es_MX", "es-MX", false),
        ("fr_FR", "en-US", true)
    ])
    func responseNamesTheRenderingLanguage(locale: String, language: String, carriesText: Bool) throws {
        let responses = QuestionnaireResponses(questionnaire: Self.questionnaire())
        responses.responses["mood"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/mood|good"])))
        let pair = try ResourceBuilder().pair(
            from: responses,
            renderedIn: Locale(identifier: locale),
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        #expect(pair.response.language?.value?.string == language)
        let section = try #require(pair.response.item?.first)
        let group = try #require(section.item?.first)
        let mood = try #require(group.item?.first)
        #expect(section.text?.value?.string == (carriesText ? "Today" : nil))
        #expect(group.text?.value?.string == (carriesText ? "Feelings" : nil))
        #expect(mood.text?.value?.string == (carriesText ? "How do you feel?" : nil))
        // A translated response identifies the answer by system and code alone.
        guard case .coding(let coding)? = mood.answer?.first?.value else {
            Issue.record("Expected a coded answer")
            return
        }
        #expect(coding.code?.value?.string == "good")
        #expect(coding.display?.value?.string == (carriesText ? "Good" : nil))
        #expect(coding.display?.extension == nil)
    }

    @Test
    func importKeepsTranslationsOfTheDisplayedValueOfAStringOption() throws {
        var value: FHIRPrimitive<ModelsR4.FHIRString> = "meh"
        var translation = Extension(url: "http://hl7.org/fhir/StructureDefinition/translation")
        translation.extension = [
            Extension(url: "lang", value: .code("es")),
            Extension(url: "content", value: .string("regular"))
        ]
        value.extension = [translation]
        var item = ModelsR4.QuestionnaireItem(linkId: "mood".asFHIRStringPrimitive(), type: .init(.choice))
        item.text = "How do you feel?"
        item.answerOption = [.init(value: .string(value))]
        var fhirQuestionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        fhirQuestionnaire.url = "https://example.org/fhir/Questionnaire/string-option".asFHIRURIPrimitive()
        fhirQuestionnaire.version = "1.0.0".asFHIRStringPrimitive()
        fhirQuestionnaire.language = "en"
        fhirQuestionnaire.item = [item]
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire, clock: questionnaireResponseTestClock)
        guard case .choice(let config)? = questionnaire.sections.first?.tasks.first?.kind.variant else {
            Issue.record("Expected a choice")
            return
        }
        #expect(config.options.first?.title == Text("meh", translations: ["es": "regular"]))
        #expect(config.options.first?.answerValue == .string("meh"))
    }
}
