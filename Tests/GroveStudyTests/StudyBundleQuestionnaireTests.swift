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
    private static let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Valid", fileExtension: "json")
    private static let esUS = LocalizationKey(language: .spanish, region: .unitedStates)

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

    private static func englishQuestionnaire() throws -> ModelsR4.Questionnaire {
        let url = try #require(Bundle.module.url(forResource: "Valid+en-US", withExtension: "json"))
        return try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(contentsOf: url))
    }

    /// The same questionnaire written in Spanish: every text suffixed, the structure untouched.
    private static func spanishQuestionnaire() throws -> ModelsR4.Questionnaire {
        var questionnaire = try englishQuestionnaire()
        questionnaire.language = "es-US"
        questionnaire.title = "Válido"
        questionnaire.item = questionnaire.item?.map { item in
            var item = item
            item.text = item.text?.value.map { "\($0.string) (es)".asFHIRStringPrimitive() }
            item.answerOption = item.answerOption?.map { option in
                guard case .coding(var coding) = option.value else {
                    return option
                }
                coding.display = coding.display?.value.map { "\($0.string) (es)".asFHIRStringPrimitive() }
                return .init(value: .coding(coding))
            }
            return item
        }
        return questionnaire
    }

    private static func temporaryBundleUrl() -> URL {
        URL.temporaryDirectory.appending(component: "\(UUID().uuidString).\(StudyBundle.fileExtension)", directoryHint: .isDirectory)
    }

    private static func expectMerged(_ questionnaire: ModelsR4.Questionnaire?) throws {
        let questionnaire = try #require(questionnaire)
        #expect(questionnaire.language?.value?.string == "en-US")
        #expect(questionnaire.title?.value?.string == "Valid")
        #expect(questionnaire.title?.translations == ["es-US": "Válido"])
        let items = questionnaire.item ?? []
        #expect(items.map { $0.text?.translations ?? [:] } == [
            ["es-US": "Instruction Component (US) (es)"],
            ["es-US": "Boolean Question (US) (es)"],
            ["es-US": "Date Question (US) (es)"],
            ["es-US": "Select a Letter (es)"]
        ])
        let displays = items.last?.answerOption?.map { option -> [String: String] in
            guard case .coding(let coding) = option.value else {
                return [:]
            }
            return coding.display?.translations ?? [:]
        }
        #expect(displays == [["es-US": "A (es)"], ["es-US": "B (es)"], ["es-US": "C (es)"]])
    }

    @Test
    func writingMergesEachQuestionnaireIntoOneMultilingualFile() throws {
        let bundleUrl = Self.temporaryBundleUrl()
        defer {
            try? FileManager.default.removeItem(at: bundleUrl)
        }
        let bundle = try StudyBundle.writeToDisk(at: bundleUrl, definition: Self.definition, files: [
            .init(fileRef: Self.fileRef, localization: .enUS, contents: try JSONEncoder().encode(Self.englishQuestionnaire())),
            .init(fileRef: Self.fileRef, localization: Self.esUS, contents: try JSONEncoder().encode(Self.spanishQuestionnaire()))
        ])
        let files = try FileManager.default.contentsOfDirectory(
            at: bundleUrl.appending(component: "questionnaire"),
            includingPropertiesForKeys: nil
        )
        #expect(files.map(\.lastPathComponent) == ["Valid+en-US.json"])
        try Self.expectMerged(bundle.questionnaire(for: Self.fileRef))
        #expect(try bundle.validate().isEmpty)
        let component = try #require(bundle.studyDefinition.components.first)
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "es_MX")) == "Válido")
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "en_US")) == "Valid")
        #expect(bundle.displayTitle(for: component, in: Locale(identifier: "fr_FR")) == "Valid")
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
        try JSONEncoder().encode(Self.englishQuestionnaire()).write(to: folder.appending(component: "Valid+en-US.json"))
        try JSONEncoder().encode(Self.spanishQuestionnaire()).write(to: folder.appending(component: "Valid+es-US.json"))
        let bundle = try StudyBundle(bundleUrl: bundleUrl)
        try Self.expectMerged(bundle.questionnaire(named: "Valid"))
    }

    @Test
    func perLocaleFilesMustShareOneCanonical() throws {
        var spanish = try Self.spanishQuestionnaire()
        spanish.version = "2.0.0"
        let bundleUrl = Self.temporaryBundleUrl()
        let error = #expect(throws: StudyBundle.CreateBundleError.self) {
            try StudyBundle.writeToDisk(at: bundleUrl, definition: Self.definition, files: [
                .init(fileRef: Self.fileRef, localization: .enUS, contents: try JSONEncoder().encode(Self.englishQuestionnaire())),
                .init(fileRef: Self.fileRef, localization: Self.esUS, contents: try JSONEncoder().encode(spanish))
            ])
        }
        guard case .failedValidation(let issues)? = error else {
            Issue.record("Expected a validation failure")
            return
        }
        #expect(issues == [
            .questionnaire(.mismatchingFieldValues(
                baseFileRef: .init(fileRef: Self.fileRef, localization: .enUS),
                localizedFileRef: .init(fileRef: Self.fileRef, localization: Self.esUS),
                path: StudyBundle.BundleValidationIssue.QuestionnaireIssue.Path.version,
                baseValue: nil,
                localizedValue: .init("2.0.0")
            ))
        ])
    }
}
