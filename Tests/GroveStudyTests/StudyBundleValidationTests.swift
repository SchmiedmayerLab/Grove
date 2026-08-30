//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable function_body_length file_length file_types_order

import Foundation
import GroveFoundation
import GroveLocalization
@_spi(APISupport)
@testable import GroveStudyDefinition
import ModelsR4
import Testing


@Suite
struct StudyBundleValidationTests { // swiftlint:disable:this type_body_length
    private typealias Path = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Path
    private typealias Value = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Value
    
    @Test
    func validInput() throws {
        let testStudy = StudyDefinition(
            studyRevision: 0,
            metadata: .init(
                id: UUID(),
                title: .init(),
                explanationText: .init(),
                shortExplanationText: .init(),
                participationCriterion: true
            ),
            components: [
                .informational(.init(
                    id: UUID(),
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md")
                )),
                .questionnaire(.init(
                    id: UUID(),
                    fileRef: .init(category: .questionnaire, filename: "Valid", fileExtension: "json")
                ))
            ],
            componentSchedules: []
        )
        let tmpUrl = URL.temporaryDirectory.appending(component: "\(UUID().uuidString).\(StudyBundle.fileExtension)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tmpUrl)
        }
        // this not failing means that the validation successfully ran, and found no issues.
        _ = try StudyBundle.writeToDisk(
            at: tmpUrl,
            definition: testStudy,
            files: [
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                    localization: .init(language: .english, region: .unitedStates),
                    contents: """
                        ---
                        title: Welcome to our Study!
                        id: 4A6A052E-5FE6-4FFA-92D5-DA605E12E97E
                        ---
                        """
                ),
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                    localization: .init(language: .spanish, region: .unitedStates),
                    contents: """
                        ---
                        title: Bienvenido a nuestro estudio!
                        id: 4A6A052E-5FE6-4FFA-92D5-DA605E12E97E
                        ---
                        """
                ),
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .questionnaire, filename: "Valid", fileExtension: "json"),
                    localization: .enUS,
                    contentsOf: try #require(Bundle.module.url(forResource: "Valid+en-US", withExtension: "json"))
                ),
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .questionnaire, filename: "Valid", fileExtension: "json"),
                    localization: .enGB,
                    contentsOf: try #require(Bundle.module.url(forResource: "Valid+en-GB", withExtension: "json"))
                )
            ]
        )
    }
    
    
    @Test
    func invalidArticleInputMissingId() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeStudyForArticleValidation(
                enUSExtraMetadata: [],
                esUSExtraMetadata: []
            )
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .informationalArticle, filename: "a1", fileExtension: "md")
            #expect(Set(issues) == [
                .article(.documentMetadataMissingId(fileRef: .init(fileRef: fileRef, localization: .enUS))),
                .article(.documentMetadataMissingId(fileRef: .init(fileRef: fileRef, localization: .esUS)))
            ])
        default:
            throw error
        }
    }
    
    @Test
    func invalidArticleInputMismatchedId() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeStudyForArticleValidation(
                enUSExtraMetadata: [("id", "A5958A33-D93E-49D5-A0C6-3708CA97D431")],
                esUSExtraMetadata: [("id", "1EED6D54-1462-4DAC-9ED9-D39AE9CE01DB")]
            )
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .informationalArticle, filename: "a1", fileExtension: "md")
            #expect(issues == [
                .article(.documentMetadataIdMismatchToBase(
                    baseLocalization: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .esUS),
                    baseId: "A5958A33-D93E-49D5-A0C6-3708CA97D431",
                    localizedFileRefId: "1EED6D54-1462-4DAC-9ED9-D39AE9CE01DB"
                ))
            ])
        default:
            throw error
        }
    }
    
    
    // test that we expect the questionnaire's language field to be equal to the language in the filename's localization component.
    @Test
    func questionnaireLocalizationLanguageMismatch() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid3", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Invalid3+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Invalid3+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid3", fileExtension: "json")
            #expect(Set(issues) == [
                .questionnaire(.languageDiffersFromFilenameLocalization(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    questionnaireLanguage: "en-US"
                ))
            ])
        default:
            throw error
        }
    }
    
    
    // test that we expect the questionnaire's language field to be parsable into a `LocalizationKey`.
    @Test
    func questionnaireInvalidLocalization() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid4", fileExtension: "json"), localizations: [
                    .init(key: .esUS, url: try #require(Bundle.module.url(forResource: "Invalid4+es-US", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid4", fileExtension: "json")
            #expect(Set(issues) == [
                .questionnaire(.invalidField(
                    fileRef: .init(fileRef: fileRef, localization: .esUS),
                    path: .root.language,
                    fieldValue: .init("es"),
                    failureReason: "failed to parse into a `LocalizationKey`"
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func invalidQuestionnaireLocalizations() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid1", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Invalid1+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Invalid1+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid1", fileExtension: "json")
            #expect(Set(issues) == [
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.id,
                    baseValue: .init("0C0D66EB-DF6E-43CA-B8E6-8653DB5D1610"),
                    localizedValue: .init("C8F9D485-3A88-4416-92EE-839CC1974AFC")
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[2].type,
                    baseValue: .init(QuestionnaireItemType.date),
                    localizedValue: .init(QuestionnaireItemType.integer)
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func invalidQuestionnaireLocalizations2() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid2", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Invalid2+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Invalid2+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid2", fileExtension: "json")
            #expect(Set(issues) == [
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.id
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.id,
                    baseValue: .init("0C0D66EB-DF6E-43CA-B8E6-8653DB5D1610"),
                    localizedValue: nil
                )),
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    path: .root.title
                )),
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    path: .root.item[1].text
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func invalidQuestionnaireLocalizations3() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Empty", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Empty+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Empty+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Empty", fileExtension: "json")
            #expect(Set(issues) == [
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    path: .root.item,
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item.length,
                    baseValue: .init(0),
                    localizedValue: .init(1)
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func missingFileRef() throws {
        let definition = StudyDefinition(
            studyRevision: 0,
            metadata: .init(
                id: UUID(),
                title: .init(),
                explanationText: .init(),
                shortExplanationText: .init(),
                participationCriterion: true
            ),
            components: [
                .informational(.init(
                    id: UUID(),
                    fileRef: .init(category: .informationalArticle, filename: "Article", fileExtension: "md")
                ))
            ],
            componentSchedules: []
        )
        do {
            let tmpUrl = URL.temporaryDirectory.appending(component: "\(UUID().uuidString).\(StudyBundle.fileExtension)", directoryHint: .isDirectory)
            defer {
                try? FileManager.default.removeItem(at: tmpUrl)
            }
            let error = try #require(throws: (StudyBundle.CreateBundleError).self) {
                try StudyBundle.writeToDisk(at: tmpUrl, definition: definition, files: [])
            }
            switch error {
            case .failedValidation(let issues):
                #expect(Set(issues) == [
                    .general(.noFilesMatchingFileRef(.init(category: .informationalArticle, filename: "Article", fileExtension: "md")))
                ])
            default:
                throw error
            }
        }
    }
    
    
    @Test
    func conflictingChoiceOptions() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "ChoiceOptionConflict", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "ChoiceOptionConflict+en-US", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "ChoiceOptionConflict", fileExtension: "json")
            expectEqualIgnoringOrder(Set(issues), [
                .questionnaire(.conflictingFieldValues(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    fstPath: Path.item[0].answerOption[1].valueCoding.display,
                    fstValue: .init("B"),
                    sndPath: Path.item[2].answerOption[1].valueCoding.display,
                    sndValue: .init("C"),
                    comment: "Both options have code 'b' in system 'urn:uuid:4cf7ebf9-1fe3-40d1-96fb-a84f3105b3ac', but they have different titles."
                )),
                .questionnaire(.conflictingFieldValues(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    fstPath: Path.item[0].answerOption[2].valueCoding.display,
                    fstValue: .init("C"),
                    sndPath: Path.item[1].answerOption[1].valueCoding.display,
                    sndValue: .init("B"),
                    comment: "Both options have code 'c' in system 'urn:uuid:4cf7ebf9-1fe3-40d1-96fb-a84f3105b3ac', but they have different titles."
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func duplicateChoiceOptions() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "ChoiceOptionDuplicate", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "ChoiceOptionDuplicate+en-US", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "ChoiceOptionDuplicate", fileExtension: "json")
            expectEqualIgnoringOrder(Set(issues), [
                .questionnaire(.conflictingFieldValues(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    fstPath: Path.item[0].answerOption[0].valueCoding.display,
                    fstValue: .init("A"),
                    sndPath: Path.item[0].answerOption[1].valueCoding.display,
                    sndValue: .init("B"),
                    comment: "Both options have code 'a' in system 'urn:uuid:4cf7ebf9-1fe3-40d1-96fb-a84f3105b3ac', but they have different titles."
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func mismatchingEnableWhenConditions() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "TestSurvey", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "TestSurvey+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "TestSurvey+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "TestSurvey", fileExtension: "json")
            expectEqualIgnoringOrder(Set(issues), [
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[1].enableWhen[0].answer.coding.code,
                    baseValue: .init("a"),
                    localizedValue: .init("b")
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: Path.item[0].answerOption.length,
                    baseValue: .init(3),
                    localizedValue: .init(4)
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func mismatchingNumberInputBounds() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid5", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Invalid5+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Invalid5+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid5", fileExtension: "json")
            expectEqualIgnoringOrder(Set(issues), [
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[1].extensions["http://hl7.org/fhir/StructureDefinition/minValue"],
                    comment: "Value in base: integer(1)"
                )),
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[1].extensions["http://hl7.org/fhir/StructureDefinition/maxValue"],
                    comment: "Value in base: integer(10)"
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0].extensions["http://hl7.org/fhir/StructureDefinition/minValue"].valueInteger,
                    baseValue: Value(7),
                    localizedValue: Value(5)
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0].extensions["http://hl7.org/fhir/StructureDefinition/maxValue"].valueInteger,
                    baseValue: Value(12),
                    localizedValue: Value(15)
                ))
            ])
        default:
            throw error
        }
    }
    
    
    @Test
    func missingQuestionSpecificExtensions() throws {
        let error = try #require(throws: StudyBundle.CreateBundleError.self) {
            try makeTestStudy(articles: [], questionnaires: [
                .init(fileRef: .init(category: .questionnaire, filename: "Invalid6", fileExtension: "json"), localizations: [
                    .init(key: .enUS, url: try #require(Bundle.module.url(forResource: "Invalid6+en-US", withExtension: "json"))),
                    .init(key: .enGB, url: try #require(Bundle.module.url(forResource: "Invalid6+en-GB", withExtension: "json")))
                ])
            ])
        }
        switch error {
        case .failedValidation(let issues):
            let fileRef = StudyBundle.FileReference(category: .questionnaire, filename: "Invalid6", fileExtension: "json")
            expectEqualIgnoringOrder(Set(issues), [
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enUS),
                    path: .root.item[1].extensions["http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"],
                    comment: "'http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption' is a required extension in this context"
                )),
                .questionnaire(.missingField(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[1].extensions["http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"],
                    comment: "'http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption' is a required extension in this context"
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0]
                        .extensions["http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity"]
                        .valueQuantity.value,
                    baseValue: Value(1),
                    localizedValue: Value(2)
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0]
                        .extensions["http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity"]
                        .valueQuantity.system,
                    baseValue: Value(URL(string: "http://unitsofmeasure.org")),
                    localizedValue: Value(URL(string: "https://example.org/units"))
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0]
                        .extensions["http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity"]
                        .valueQuantity.code,
                    baseValue: Value("kg"),
                    localizedValue: Value("g")
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0]
                        .extensions["http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"]
                        .valueCoding.system,
                    baseValue: Value(URL(string: "http://unitsofmeasure.org")),
                    localizedValue: Value(URL(string: "https://example.org/units"))
                )),
                .questionnaire(.mismatchingFieldValues(
                    baseFileRef: .init(fileRef: fileRef, localization: .enUS),
                    localizedFileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[0]
                        .extensions["http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"]
                        .valueCoding.code,
                    baseValue: Value("kg"),
                    localizedValue: Value("g")
                )),
                .questionnaire(.invalidField(
                    fileRef: .init(fileRef: fileRef, localization: .enGB),
                    path: .root.item[2]
                        .extensions["http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"]
                        .length,
                    fieldValue: Value(2),
                    failureReason: "Grove study definitions currently require exactly one extension entry for 'http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption'"
                ))
            ])
        default:
            throw error
        }
    }
}


@Suite
struct StudyBundleValidationUtilsTests {
    private typealias Path = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Path
    private typealias Value = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Value
    
    @Test
    func path() {
        #expect(Path.root.item[1].enableWhen[1].answer.coding.code == Path([
            .field(name: "item"),
            .subscript(idx: 1),
            .field(name: "enableWhen"),
            .subscript(idx: 1),
            .field(name: "answer"),
            .field(name: "coding"),
            .field(name: "code")
        ]))
        // swiftlint:disable:next identical_operands
        #expect(Path.root.item[1].enableWhen[0].answer.coding.code == Path.root.item[1].enableWhen[0].answer.coding.code)
        #expect(Path.root.a.b.c[1] == Path.a.b.c[1])
    }
    
    @Test
    func valueInitFromOptional() {
        let expected = Value(52)
        #expect(Value(52) == expected)
        #expect(Value(Optional(52)) == expected)
        #expect(Value(Optional(Optional(52))) == expected)
        #expect(Value(Optional(Optional(Optional(52)))) == expected)
        #expect(Value(Optional(Optional(Optional(Optional(52))))) == expected)
        #expect(Value(Optional(Optional(Optional(Optional(Optional(52)))))) == expected)
        #expect(Value(Optional(Optional(Optional(Optional(Optional(Optional(52))))))) == expected)
        #expect(Value(Optional(Optional(Optional(Optional(Optional(Optional(Optional(52)))))))) == expected)
    }
    
    @Test
    func valueInitFromFHIRPrimitive() {
        #expect(Value(FHIRString("abc")) == Value("abc"))
        #expect(Value(Optional(FHIRString("abc"))) == Value("abc"))
        #expect(Value(FHIRString("abc")) == Value(Optional("abc")))
        #expect(Value(Optional(FHIRString("abc"))) == Value(Optional("abc")))
        #expect(Value(FHIRPrimitive(FHIRString("abc"))) == Value("abc"))
        #expect(Value(Optional(FHIRPrimitive(FHIRString("abc")))) == Value("abc"))
        #expect(Value(FHIRPrimitive(FHIRString("abc"))) == Value(Optional("abc")))
        #expect(Value(Optional(FHIRPrimitive(FHIRString("abc")))) == Value(Optional("abc")))
    }
    
    @Test
    func valueInitFHIRInteger() {
        #expect(Value(FHIRPrimitive(FHIRInteger(12))) == Value(12))
        #expect(Value(FHIRPrimitive(FHIRInteger(12))) == Value(12 as Int32))
        #expect(Value(FHIRPrimitive(FHIRInteger(12))) == Value(12 as UInt32))
        #expect(Value(FHIRPrimitive(FHIRInteger(12))) == Value(12 as Int64))
        #expect(Value(FHIRPrimitive(FHIRInteger(12))) == Value(12 as UInt64))
    }
    
    @Test
    func valueInitFHIRDecimal() {
        #expect(Value(FHIRPrimitive(FHIRDecimal(4.7))) == Value(4.7))
        #expect(Value(FHIRPrimitive(FHIRDecimal(4))) == Value(4))
    }
}


// MARK: Utils

extension StudyBundleValidationTests {
    private struct TestStudyArticleInput {
        struct Localization {
            let key: LocalizationKey
            let contents: String
        }
        let fileRef: StudyBundle.FileReference
        let localizations: [Localization]
    }
    
    private struct TestStudyQuestionnaireInput {
        struct Localization {
            let key: LocalizationKey
            let url: URL
        }
        let fileRef: StudyBundle.FileReference
        let localizations: [Localization]
    }
    
    private func makeTestStudy(
        articles: [TestStudyArticleInput],
        questionnaires: [TestStudyQuestionnaireInput]
    ) throws -> StudyBundle {
        let testStudy = StudyDefinition(
            studyRevision: 0,
            metadata: .init(
                id: UUID(),
                title: .init(),
                explanationText: .init(),
                shortExplanationText: .init(),
                participationCriterion: true
            ),
            components: Array {
                for article in articles {
                    .informational(.init(id: UUID(), fileRef: article.fileRef))
                }
                for questionnaire in questionnaires {
                    .questionnaire(.init(id: UUID(), fileRef: questionnaire.fileRef))
                }
            },
            componentSchedules: []
        )
        let tmpUrl = URL.temporaryDirectory.appending(component: "\(UUID().uuidString).\(StudyBundle.fileExtension)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: tmpUrl)
        }
        func makeArticle1(localization: LocalizationKey, metadata: [(String, String)]) throws -> StudyBundle.FileResourceInput {
            try StudyBundle.FileResourceInput(
                fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                localization: localization,
                contents: { () -> String in
                    let metadata = metadata.map { "\($0): \($1)" }.joined(separator: "\n")
                    return metadata.isEmpty ? "---\n---" : "---\n\(metadata)\n---"
                }()
            )
        }
        return try StudyBundle.writeToDisk(
            at: tmpUrl,
            definition: testStudy,
            files: try Array {
                for article in articles {
                    for localization in article.localizations {
                        try StudyBundle.FileResourceInput(fileRef: article.fileRef, localization: localization.key, contents: localization.contents)
                    }
                }
                for questionnaire in questionnaires {
                    for localization in questionnaire.localizations {
                        StudyBundle.FileResourceInput(fileRef: questionnaire.fileRef, localization: localization.key, contentsOf: localization.url)
                    }
                }
            }
        )
    }
    
    
    /// Creates a temporary study bundle for testing article validation
    private func makeStudyForArticleValidation(
        enUSExtraMetadata: [(String, String)],
        esUSExtraMetadata: [(String, String)]
    ) throws -> StudyBundle {
        func makeArticleLocalization(for key: LocalizationKey, metadata: [(String, String)]) -> TestStudyArticleInput.Localization {
            var lines = ["---"]
            for (key, value) in metadata {
                lines.append("\(key): \(value)")
            }
            lines.append("---")
            return .init(key: key, contents: lines.joined(separator: "\n") + "\n")
        }
        return try makeTestStudy(
            articles: [
                .init(fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"), localizations: [
                    makeArticleLocalization(for: .enUS, metadata: [("title", "Welcome to our Study!")] + enUSExtraMetadata),
                    makeArticleLocalization(for: .esUS, metadata: [("title", "Bienvenido a nuestro estudio!")] + esUSExtraMetadata)
                ])
            ],
            questionnaires: []
        )
    }
}


extension LocalizationKey {
    static let esUS = Self(language: .spanish, region: .unitedStates)
    static let enGB = Self(language: .english, region: .unitedKingdom)
}
