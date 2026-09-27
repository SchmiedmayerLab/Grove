//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveLocalization
@_spi(APISupport)
@testable import GroveStudyDefinition
import ModelsR4
import Testing


@Suite
struct StudyBundleQuestionnaireTests {
    private typealias JSONObject = [String: Any]
    private typealias Path = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Path

    private static let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Survey", fileExtension: "json")
    private static let esUS = LocalizationKey(language: .spanish, region: .unitedStates)

    /// A questionnaire with every kind of displayed string Grove renders, each one starting with `Text`, so the
    /// Spanish source differs from it in presentation text and nowhere else.
    private static let english = #"""
    {
      "resourceType": "Questionnaire",
      "id": "survey",
      "url": "https://example.org/fhir/Questionnaire/survey",
      "version": "1.0.0",
      "language": "en-US",
      "status": "active",
      "title": "Text Survey",
      "description": "Text description",
      "purpose": "Text purpose",
      "copyright": "Text copyright",
      "item": [
        {
          "linkId": "intro",
          "type": "display",
          "text": "Text intro",
          "_text": {
            "extension": [{"url": "http://hl7.org/fhir/StructureDefinition/rendering-markdown", "valueMarkdown": "Text **intro**"}]
          }
        },
        {
          "linkId": "mood",
          "type": "choice",
          "text": "Text mood?",
          "prefix": "Text 1.",
          "code": [{"system": "http://loinc.org", "code": "1234-5", "display": "Text mood code"}],
          "extension": [{"url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText", "valueString": "Text mood"}],
          "answerOption": [{
            "valueCoding": {"system": "https://example.org/mood", "code": "good", "display": "Text good"},
            "extension": [{"url": "http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix", "valueString": "Text A."}]
          }]
        },
        {
          "linkId": "pressure",
          "type": "quantity",
          "text": "Text pressure",
          "extension": [
            {
              "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption",
              "valueCoding": {"system": "http://unitsofmeasure.org", "code": "mm[Hg]", "display": "Text millimeters of mercury"}
            },
            {
              "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity",
              "valueQuantity": {"value": 40, "unit": "Text millimeters of mercury", "system": "http://unitsofmeasure.org", "code": "mm[Hg]"}
            },
            {
              "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtractCategory",
              "valueCodeableConcept": {
                "coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "vital-signs", "display": "Text vital signs"}]
              }
            },
            {
              "url": "http://hl7.org/fhir/StructureDefinition/targetConstraint",
              "extension": [
                {"url": "key", "valueId": "pressure-1"},
                {"url": "severity", "valueCode": "error"},
                {"url": "expression", "valueExpression": {"language": "text/fhirpath", "expression": "answer.value.value < 300"}},
                {"url": "human", "valueString": "Text too high"}
              ]
            }
          ]
        },
        {
          "linkId": "note",
          "type": "string",
          "text": "Text note",
          "extension": [
            {"url": "http://hl7.org/fhir/StructureDefinition/entryFormat", "valueString": "Text e.g. walking"},
            {"url": "http://hl7.org/fhir/StructureDefinition/regex", "valueString": "^[a-z ]+$"}
          ]
        }
      ]
    }
    """#

    private static var definition: StudyDefinition {
        StudyDefinition(
            studyRevision: 0,
            metadata: .init(
                id: UUID(),
                title: .init(),
                explanationText: .init(),
                shortExplanationText: .init(),
                participationCriterion: true
            ),
            components: [.questionnaire(.init(id: UUID(), fileRef: fileRef))],
            componentSchedules: []
        )
    }

    /// The Spanish source: every presentation string translated, the data untouched unless `editing` changes it.
    private static func spanish(editing edit: (inout String) -> Void = { _ in }) -> String {
        var spanish = english
            .replacingOccurrences(of: "\"language\": \"en-US\"", with: "\"language\": \"es-US\"")
            .replacingOccurrences(of: "Text ", with: "Texto ")
        edit(&spanish)
        return spanish
    }

    private static func questionnaire(_ json: String) throws -> ModelsR4.Questionnaire {
        try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(json.utf8))
    }

    private static func temporaryBundleUrl() -> URL {
        URL.temporaryDirectory.appending(component: "\(UUID().uuidString).\(StudyBundle.fileExtension)", directoryHint: .isDirectory)
    }

    private static func writeBundle(spanish: String, to bundleUrl: URL) throws -> StudyBundle {
        try StudyBundle.writeToDisk(at: bundleUrl, definition: definition, files: [
            .init(fileRef: fileRef, localization: .enUS, contents: english),
            .init(fileRef: fileRef, localization: esUS, contents: spanish)
        ])
    }

    /// Every base string of the merged questionnaire with the translations it carries, by language.
    private static func translatedStrings(in value: Any, into result: inout [(base: String, translations: [String: String])]) {
        if let object = value as? JSONObject {
            for (key, child) in object {
                if let base = child as? String, let primitive = object["_\(key)"] as? JSONObject {
                    var translations: [String: String] = [:]
                    for ext in primitive["extension"] as? [JSONObject] ?? []
                    where ext["url"] as? String == "http://hl7.org/fhir/StructureDefinition/translation" {
                        let parts = ext["extension"] as? [JSONObject] ?? []
                        let lang = parts.first { $0["url"] as? String == "lang" }?["valueCode"] as? String ?? ""
                        #expect(translations[lang] == nil, "at most one translation per language")
                        translations[lang] = parts.first { $0["url"] as? String == "content" }?["valueString"] as? String
                    }
                    if !translations.isEmpty {
                        result.append((base, translations))
                    }
                }
                translatedStrings(in: child, into: &result)
            }
        } else if let array = value as? [Any] {
            for element in array {
                translatedStrings(in: element, into: &result)
            }
        }
    }

    private static func strings(in value: Any) -> [String] {
        if let string = value as? String {
            [string]
        } else if let object = value as? JSONObject {
            object.values.flatMap(strings(in:))
        } else if let array = value as? [Any] {
            array.flatMap(strings(in:))
        } else {
            []
        }
    }

    @Test
    func mergingCarriesEverySpanishStringAsATranslation() throws {
        let bundleUrl = Self.temporaryBundleUrl()
        defer {
            try? FileManager.default.removeItem(at: bundleUrl)
        }
        let bundle = try Self.writeBundle(spanish: Self.spanish(), to: bundleUrl)
        let files = try FileManager.default.contentsOfDirectory(
            at: bundleUrl.appending(component: "questionnaire"),
            includingPropertiesForKeys: nil
        )
        #expect(files.map(\.lastPathComponent) == ["Survey+en-US.json"])
        #expect(try bundle.validate().isEmpty)

        let merged = try #require(bundle.questionnaire(for: Self.fileRef))
        #expect(merged.language?.value?.string == "en-US")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged))
        var translated: [(base: String, translations: [String: String])] = []
        Self.translatedStrings(in: json, into: &translated)
        let englishTexts = Self.strings(in: try JSONSerialization.jsonObject(with: Data(Self.english.utf8))).filter { $0.hasPrefix("Text ") }
        #expect(englishTexts.count == 19)
        #expect(translated.map(\.base).sorted() == englishTexts.sorted())
        for (base, translations) in translated {
            #expect(translations == ["es-US": base.replacingOccurrences(of: "Text ", with: "Texto ")])
        }
    }

    @Test
    func displayTitlesRenderInTheLocalesLanguage() throws {
        let bundleUrl = Self.temporaryBundleUrl()
        defer {
            try? FileManager.default.removeItem(at: bundleUrl)
        }
        let bundle = try Self.writeBundle(spanish: Self.spanish(), to: bundleUrl)
        let component = try #require(bundle.studyDefinition.components.first)
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "es_MX")) == "Texto Survey")
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "en_US")) == "Text Survey")
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "fr_FR")) == "Text Survey")
        #expect(bundle.displaySubtitle(for: component, in: Locale(identifier: "es_US")) == "Texto purpose")
    }

    @Test
    func loadingMergesABundleStillCarryingPerLocaleFiles() throws {
        let bundleUrl = Self.temporaryBundleUrl()
        defer {
            try? FileManager.default.removeItem(at: bundleUrl)
        }
        let folder = bundleUrl.appending(component: "questionnaire")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Self.definition).write(to: bundleUrl.appending(component: "definition.json"))
        try Data(Self.english.utf8).write(to: folder.appending(component: "Survey+en-US.json"))
        try Data(Self.spanish().utf8).write(to: folder.appending(component: "Survey+es-US.json"))
        let merged = try #require(StudyBundle(bundleUrl: bundleUrl).questionnaire(named: "Survey"))
        #expect(merged.title?.translations == ["es-US": "Texto Survey"])
        #expect(merged.item?.first?.text?.translations == ["es-US": "Texto intro"])
    }

    @Test("Data that differs between locale sources fails validation instead of merging", arguments: [
        ("\"code\": \"good\"", "\"code\": \"bueno\"", "item[1].answerOption[0].valueCoding.code"),
        (
            "\"code\": \"vital-signs\"",
            "\"code\": \"signos-vitales\"",
            "item[2].extension[\"http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtractCategory\"]"
                + ".valueCodeableConcept.coding[0].code"
        ),
        ("^[a-z ]+$", "^[a-zñ ]+$", "item[3].extension[\"http://hl7.org/fhir/StructureDefinition/regex\"].valueString")
    ])
    func differingDataFailsValidation(original: String, replacement: String, path: String) throws {
        let bundleUrl = Self.temporaryBundleUrl()
        let spanish = Self.spanish { $0 = $0.replacingOccurrences(of: original, with: replacement) }
        let error = #expect(throws: StudyBundle.CreateBundleError.self) {
            try Self.writeBundle(spanish: spanish, to: bundleUrl)
        }
        guard case .failedValidation(let issues)? = error else {
            Issue.record("Expected a validation failure")
            return
        }
        #expect(issues.count == 1)
        guard case .questionnaire(.mismatchingFieldValues(_, let localized, let issuePath, _, _))? = issues.first else {
            Issue.record("Expected a mismatching field value")
            return
        }
        #expect(localized.localization == Self.esUS)
        #expect(issuePath.description == path)
    }

    @Test
    func aStringAnswerOptionIsData() throws {
        var base = try Self.questionnaire(#"{"resourceType": "Questionnaire", "status": "active", "language": "en-US", "item": [{"linkId": "q", "type": "choice", "answerOption": [{"valueString": "yes"}]}]}"#)
        let other = try Self.questionnaire(#"{"resourceType": "Questionnaire", "status": "active", "language": "es-US", "item": [{"linkId": "q", "type": "choice", "answerOption": [{"valueString": "sí"}]}]}"#)
        let conflicts = try base.addTranslations(from: other, in: "es-US")
        #expect(conflicts.map(\.path.description) == ["item[0].answerOption[0].valueString"])
    }

    @Test
    func perLocaleFilesMustShareOneCanonical() throws {
        let bundleUrl = Self.temporaryBundleUrl()
        let spanish = Self.spanish { $0 = $0.replacingOccurrences(of: "\"version\": \"1.0.0\"", with: "\"version\": \"2.0.0\"") }
        let error = #expect(throws: StudyBundle.CreateBundleError.self) {
            try Self.writeBundle(spanish: spanish, to: bundleUrl)
        }
        guard case .failedValidation(let issues)? = error else {
            Issue.record("Expected a validation failure")
            return
        }
        #expect(issues == [
            .questionnaire(.mismatchingFieldValues(
                baseFileRef: .init(fileRef: Self.fileRef, localization: .enUS),
                localizedFileRef: .init(fileRef: Self.fileRef, localization: Self.esUS),
                path: Path.version,
                baseValue: .init("1.0.0"),
                localizedValue: .init("2.0.0")
            ))
        ])
    }
}
