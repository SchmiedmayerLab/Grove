//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import FHIRQuestionnaires
import Foundation
import ModelsR4
import ResearchKit
@testable import ResearchKitOnFHIR
import Testing


struct FHIRToResearchKitTests {
    static let evaluationInstant = Date(timeIntervalSince1970: 1_700_000_000)
    static let evaluationTimeZone = TimeZone(secondsFromGMT: 0)! // swiftlint:disable:this force_unwrapping

    /// - Note: "FHIR extensions" here meaning Swift extensions on FHIR types, not actual FHIR extensions.
    @Test("FHIR extensions")
    func testFHIRExtensions() {
        #expect(Questionnaire.numberExample.flattenedItems.count == 3)
        #expect(Questionnaire.numberExample.flattenedQuestions.count == 3)
        #expect(Questionnaire.formExample.flattenedItems.count == 5)
        #expect(Questionnaire.formExample.flattenedQuestions.count == 3)
        #expect(Questionnaire.skipLogicExample.flattenedItems.count == 3)
        #expect(Questionnaire.skipLogicExample.flattenedQuestions.count == 3)
    }
    
    
    @Test("Create ORKNavigableOrderedTask")
    func testCreateORKNavigableOrderedTask() throws {
        let questionnaire = Questionnaire.skipLogicExample
        let task = try ORKNavigableOrderedTask(
            questionnaire: questionnaire,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        #expect(!task.steps.isEmpty)
        #expect(task.steps.count == questionnaire.flattenedItems.count)
    }
    
    
    @Test("Convert QuestionnaireItem to ORKSteps")
    func testConvertQuestionnaireItemToORKSteps() throws {
        func testQuestionnaire(_ questionnaire: Questionnaire, expectedNumSteps: Int) throws {
            let steps = try questionnaire.toORKSteps(
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
            #expect(steps.count == expectedNumSteps)
            for (item, step) in zip(questionnaire.flattenedItems, steps) {
                #expect(try #require(item.linkId.value).string == step.identifier)
            }
        }
        try testQuestionnaire(.numberExample, expectedNumSteps: 3)
        try testQuestionnaire(.formExample, expectedNumSteps: 2)
        try testQuestionnaire(.skipLogicExample, expectedNumSteps: 3)
    }
    
    
    @Test("Image capture step")
    func testImageCaptureStep() throws {
        let questionnaire = Questionnaire.imageCaptureExample
        let steps = try questionnaire.toORKSteps(
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        #expect(steps.count == 1)
    }
    
    
    @Test("Get contained value sets")
    func testGetContainedValueSets() throws {
        let valueSets = Questionnaire.containedValueSetExample.getContainedValueSets()
        #expect(valueSets.count == 1)
    }
    
    
    @Test("Item control extension")
    func testItemControlExtension() throws {
        let testItemControl = Questionnaire.sliderExample.item?.first?.itemControl
        let itemControlValue = try #require(testItemControl)
        #expect(itemControlValue == "slider")
    }

    @Test("FHIR repeats, not itemControl, determines ResearchKit multiple-choice cardinality")
    func repeatedChoiceUsesMultipleChoiceAnswerFormat() throws {
        let item = QuestionnaireItem(
            answerOption: [
                QuestionnaireItemAnswerOption(value: .coding(Coding(
                    code: "one".asFHIRStringPrimitive(),
                    display: "One".asFHIRStringPrimitive(),
                    system: "https://example.org/CodeSystem/answer".asFHIRURIPrimitive()
                )))
            ],
            linkId: "choice".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Choose all that apply".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let questionnaire = Questionnaire(
            item: [item],
            status: FHIRPrimitive(.active)
        )

        let step = try #require(try questionnaire.toORKSteps(
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        ).first as? ORKQuestionStep)
        let format = try #require(step.answerFormat as? ORKTextChoiceAnswerFormat)
        #expect(format.style == .multipleChoice)
    }

    @Test("Repeated attachment is reported as an adapter limitation")
    func repeatedAttachmentFailsPrecisely() throws {
        let item = QuestionnaireItem(
            linkId: "images".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Images".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.attachment)
        )
        let questionnaire = Questionnaire(item: [item], status: FHIRPrimitive(.active))

        #expect(throws: FHIRToResearchKitConversionError.unsupportedRepeatedItem(
            .attachment,
            linkID: "images"
        )) {
            try questionnaire.toORKSteps(
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }

    @Test("Check-box presentation cannot contradict single-answer FHIR cardinality")
    func checkboxRequiresRepeats() throws {
        var item = QuestionnaireItem(
            answerOption: [
                QuestionnaireItemAnswerOption(value: .coding(Coding(
                    code: "one".asFHIRStringPrimitive(),
                    system: "https://example.org/CodeSystem/answer".asFHIRURIPrimitive()
                )))
            ],
            linkId: "choice".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(false),
            text: "Choose".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        item.extension = [
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                value: .codeableConcept(CodeableConcept(coding: [
                    Coding(code: "check-box".asFHIRStringPrimitive())
                ]))
            )
        ]
        let questionnaire = Questionnaire(item: [item], status: FHIRPrimitive(.active))

        #expect(throws: FHIRToResearchKitConversionError.itemControlCardinalityConflict(linkID: "choice")) {
            try questionnaire.toORKSteps(
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }
    
    
    @Test("Coding Regex Pattern")
    func codingRegexPattern() throws {
        let codingWithDisplay = ValueCoding(
            code: "medication.value-yes",
            system: "http://researchkitonfhir.grovealliance.org/fhir/Coding/medication-value-exists",
            display: "Yes"
        )
        let patternWithDisplay = codingWithDisplay.patternForMatchingORKChoiceQuestionResult
        let expressionWithDisplay = try NSRegularExpression(pattern: patternWithDisplay)
        let rawValueWithDisplay = codingWithDisplay.rawValue
        #expect(!expressionWithDisplay.matches(in: rawValueWithDisplay, range: NSRange(location: 0, length: rawValueWithDisplay.count)).isEmpty)
        let codingWithoutDisplay = ValueCoding(
            code: "medication.value-yes",
            system: "http://researchkitonfhir.grovealliance.org/fhir/Coding/medication-value-exists",
            display: nil
        )
        let patternWithoutDisplay = codingWithoutDisplay.patternForMatchingORKChoiceQuestionResult
        let expressionWithoutDisplay = try NSRegularExpression(pattern: patternWithoutDisplay)
        #expect(!expressionWithoutDisplay.matches(in: rawValueWithDisplay, range: NSRange(location: 0, length: rawValueWithDisplay.count)).isEmpty)
    }
    
    
    @Test("Regex extension")
    func testRegexExtension() throws {
        let testRegex = try Questionnaire.textValidationExample.item?.first?.validationRegularExpression
        // swiftlint:disable:next line_length
        let regex = try NSRegularExpression(pattern: "^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
        #expect(regex == testRegex)
    }
    
    
    @Test("Slider step value extension")
    func testSliderStepValueExtension() throws {
        let testSliderStepValue = Questionnaire.sliderExample.item?.first?.sliderStepValue
        let sliderStepValue = try #require(testSliderStepValue)
        #expect(sliderStepValue == 1)
    }
    
    
    @Test("A regex does not infer a retired validation-message extension")
    func regexDoesNotInferValidationMessage() {
        #expect(Questionnaire.textValidationExample.item?.first?.validationMessage == nil)
    }
    
    
    @Test("Unit extension")
    func testUnitExtension() throws {
        let unit = Questionnaire.numberExample.item?[2].unit
        let unwrappedUnit = try #require(unit)
        #expect(unwrappedUnit == "g")
    }
    
    
    @Test("Minimum value extension")
    func testMinValueExtension() throws {
        let minValues = try #require(Questionnaire.numberExample.item).map { try $0.minValue }
        #expect(minValues == [
            NSNumber(value: 1),
            NSNumber(value: 1),
            NSNumber(value: 1)
        ])
    }
    
    
    @Test("Maximum value extension")
    func testMaxValueExtension() throws {
        let minValues = try #require(Questionnaire.numberExample.item).map { try $0.maxValue }
        #expect(minValues == [
            NSNumber(value: 100),
            NSNumber(value: 100),
            NSNumber(value: 100)
        ])
    }

    
    @Test("Minimum date value extension")
    func testMinDateValueExtension() throws {
        let minDateValue = try Questionnaire.dateTimeExample.item?.first?.minDateValue(
            evaluationInstant: Self.evaluationInstant
        )
        let unwrappedMinDate = try #require(minDateValue)
        #expect(unwrappedMinDate.year == 2001)
        #expect(unwrappedMinDate.month == 1)
        #expect(unwrappedMinDate.day == 1)
    }
    
    
    @Test("Maximum date value extension")
    func testMaxDateValueExtension() throws {
        let maxDateValue = try Questionnaire.dateTimeExample.item?.first?.maxDateValue(
            evaluationInstant: Self.evaluationInstant
        )
        let unwrappedMaxDate = try #require(maxDateValue)
        #expect(unwrappedMaxDate.year == 2024)
        #expect(unwrappedMaxDate.month == 1)
        #expect(unwrappedMaxDate.day == 1)
    }
    
    
    @Test("Maximum decimal extension")
    func testMaxDecimalExtension() throws {
        let maxDecimals = Questionnaire.numberExample.item?[1].maximumDecimalPlaces
        let unwrappedMaxDecimals = try #require(maxDecimals)
        #expect(unwrappedMaxDecimals == 3)
    }
}


extension FHIRToResearchKitTests {
    @Test("Questionnaire with no items")
    func testNoItemsException() throws {
        // Creates a questionnaire and set a URL, but does not add items
        let questionnaire = Questionnaire(
            status: FHIRPrimitive(PublicationStatus.draft),
            url: try #require("http://grovealliance.org/fhir/questionnaire/test".asFHIRURIPrimitive() as FHIRPrimitive<FHIRURI>?)
        )
        #expect(throws: FHIRToResearchKitConversionError.noItems) {
            try ORKNavigableOrderedTask(
                questionnaire: questionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }
    
    
    @Test("Questionnaire with no URL")
    func testNoURL() throws {
        let questionnaire = Questionnaire(
            item: [
                QuestionnaireItem(
                    linkId: FHIRPrimitive(FHIRString("intro")),
                    text: "Introduction".asFHIRStringPrimitive(),
                    type: FHIRPrimitive(QuestionnaireItemType.display)
                )
            ],
            status: FHIRPrimitive(PublicationStatus.draft)
        )
        #expect(throws: FHIRToResearchKitConversionError.missingTaskIdentifier) {
            try ORKNavigableOrderedTask(
                questionnaire: questionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
        let first = try ORKNavigableOrderedTask(
            questionnaire: questionnaire,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone,
            taskIdentifier: "study-a/introduction"
        )
        let second = try ORKNavigableOrderedTask(
            questionnaire: questionnaire,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone,
            taskIdentifier: "study-a/introduction"
        )
        #expect(first.identifier == "study-a/introduction")
        #expect(second.identifier == first.identifier)
    }

    @Test("Versioned Questionnaire canonicals produce distinct deterministic task IDs")
    func versionedCanonicalTaskIdentity() throws {
        func questionnaire(version: String) -> Questionnaire {
            Questionnaire(
                item: [
                    QuestionnaireItem(
                        linkId: "intro".asFHIRStringPrimitive(),
                        text: "Introduction".asFHIRStringPrimitive(),
                        type: FHIRPrimitive(.display)
                    )
                ],
                status: FHIRPrimitive(.active),
                url: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/Questionnaire/check-in")),
                version: version.asFHIRStringPrimitive()
            )
        }
        let version1 = try ORKNavigableOrderedTask(
            questionnaire: questionnaire(version: "1.0.0"),
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        let version2 = try ORKNavigableOrderedTask(
            questionnaire: questionnaire(version: "2.0.0"),
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        #expect(version1.identifier == "https://example.org/fhir/Questionnaire/check-in|1.0.0")
        #expect(version2.identifier == "https://example.org/fhir/Questionnaire/check-in|2.0.0")
        #expect(version1.identifier != version2.identifier)
    }

    @Test(
        "Task canonicals enforce exact unbounded SemVer",
        arguments: [
            "01.0.0",
            "1.0",
            "1.0.0-01",
            "1.0.0+",
            "1.0.0+build..two",
            " 1.0.0"
        ]
    )
    func invalidSemanticVersionsFailClosed(version: String) throws {
        let canonical = "https://example.org/fhir/Questionnaire/check-in"
        let questionnaire = Questionnaire(
            item: [
                QuestionnaireItem(
                    linkId: "intro".asFHIRStringPrimitive(),
                    text: "Introduction".asFHIRStringPrimitive(),
                    type: FHIRPrimitive(.display)
                )
            ],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: canonical)),
            version: version.asFHIRStringPrimitive()
        )

        #expect(throws: FHIRToResearchKitConversionError.invalidTaskCanonical("\(canonical)|\(version)")) {
            try ORKNavigableOrderedTask(
                questionnaire: questionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }

    @Test("SemVer validation does not impose a machine-integer width")
    func unboundedSemanticVersionIsAccepted() throws {
        let version = "184467440737095516160.0.0-alpha.1+build.7"
        #expect(ResearchKitQuestionnaireCanonical.isSemanticVersion(version))
    }

    @Test("Task canonicals reject non-HTTP schemes, fragments, and embedded separators")
    func invalidTaskCanonicalsFailClosed() throws {
        for canonical in [
            "urn:uuid:1337ec30-c182-40eb-8b79-1028af764c87",
            "https://example.org/Questionnaire/check-in#section",
            "https://example.org/Questionnaire/check-in|1.0.0"
        ] {
            let questionnaire = Questionnaire(
                item: [
                    QuestionnaireItem(
                        linkId: "intro".asFHIRStringPrimitive(),
                        text: "Introduction".asFHIRStringPrimitive(),
                        type: FHIRPrimitive(.display)
                    )
                ],
                status: FHIRPrimitive(.active),
                url: FHIRPrimitive(FHIRURI(stringLiteral: canonical))
            )
            let serializedCanonical = try #require(questionnaire.url?.value?.url.absoluteString)
            #expect(throws: FHIRToResearchKitConversionError.invalidTaskCanonical(serializedCanonical)) {
                try ORKNavigableOrderedTask(
                    questionnaire: questionnaire,
                    evaluationInstant: Self.evaluationInstant,
                    evaluationTimeZone: Self.evaluationTimeZone
                )
            }
        }

        let unversionedCanonical = "https://example.org/Questionnaire/unversioned"
        let unversioned = Questionnaire(
            item: [
                QuestionnaireItem(
                    linkId: "intro".asFHIRStringPrimitive(),
                    text: "Introduction".asFHIRStringPrimitive(),
                    type: FHIRPrimitive(.display)
                )
            ],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: unversionedCanonical))
        )
        #expect(throws: FHIRToResearchKitConversionError.invalidTaskCanonical(unversionedCanonical)) {
            try ORKNavigableOrderedTask(
                questionnaire: unversioned,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }

    @Test("Title overrides are applied to generated steps")
    func titleOverrideIsApplied() throws {
        let task = try ORKNavigableOrderedTask(
            title: "Localized title",
            questionnaire: .skipLogicExample,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        #expect(task.steps.first?.title == "Localized title")
    }

    @Test("A malformed authored bound fails the whole conversion")
    func malformedBoundFailsConversion() throws {
        let item = QuestionnaireItem(
            extension: [
                Extension(
                    url: "http://hl7.org/fhir/StructureDefinition/minValue",
                    value: .string("today( broken".asFHIRStringPrimitive())
                )
            ],
            linkId: "date".asFHIRStringPrimitive(),
            text: "Date".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.date)
        )
        let questionnaire = Questionnaire(
            item: [item],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/Questionnaire/bad-bound")),
            version: "1.0.0".asFHIRStringPrimitive()
        )
        #expect(throws: QuestionnaireItemBoundError.self) {
            try ORKNavigableOrderedTask(
                questionnaire: questionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }
}
