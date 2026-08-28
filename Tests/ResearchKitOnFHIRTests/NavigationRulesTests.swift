//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import GroveQuestionnaireFHIR
import ModelsR4
import ResearchKit
@testable import ResearchKitOnFHIR
import Testing


struct NavigationRulesTests {
    private static let evaluationInstant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let evaluationTimeZone = TimeZone(secondsFromGMT: 0)! // swiftlint:disable:this force_unwrapping

    private func createORKNavigableOrderedTask(
        firstItemID: String,
        firstItemType: QuestionnaireItemType,
        secondItemID: String,
        secondItemType: QuestionnaireItemType,
        enableWhen: QuestionnaireItemEnableWhen
    ) throws -> ORKNavigableOrderedTask {
        func answerOptions(for type: QuestionnaireItemType) -> [QuestionnaireItemAnswerOption] {
            guard type == .choice || type == .openChoice else {
                return []
            }
            return [
                QuestionnaireItemAnswerOption(value: .coding(Coding(
                    code: "testCode".asFHIRStringPrimitive(),
                    display: "Test choice".asFHIRStringPrimitive(),
                    system: "http://grovealliance.org/fhir/system/testSystem".asFHIRURIPrimitive()
                )))
            ]
        }
        let questionnaire = Questionnaire(
            item: [
                QuestionnaireItem(
                    answerOption: answerOptions(for: firstItemType),
                    linkId: FHIRPrimitive(FHIRString(firstItemID)),
                    text: FHIRPrimitive(FHIRString("First question")),
                    type: FHIRPrimitive(firstItemType)
                ),
                QuestionnaireItem(
                    answerOption: answerOptions(for: secondItemType),
                    enableWhen: [enableWhen],
                    linkId: FHIRPrimitive(FHIRString(secondItemID)),
                    text: FHIRPrimitive(FHIRString("Second question")),
                    type: FHIRPrimitive(secondItemType)
                )
            ],
            status: FHIRPrimitive(PublicationStatus.draft),
            url: FHIRPrimitive(FHIRURI(stringLiteral: "http://grovealliance.org/fhir/questionnaire/navigation-rule-test")),
            version: "1.0.0".asFHIRStringPrimitive()
        )
        return try ORKNavigableOrderedTask(
            questionnaire: questionnaire,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
    }
    @Test("Integer equal")
    func testIntegerEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .integer(100),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .integer,
            secondItemID: secondItemID,
            secondItemType: .integer,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Integer not equal")
    func testIntegerNotEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .integer(100),
            operator: FHIRPrimitive(QuestionnaireItemOperator.notEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .integer,
            secondItemID: secondItemID,
            secondItemType: .integer,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Integer less than or equal")
    func testIntegerLessThanOrEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .integer(100),
            operator: FHIRPrimitive(QuestionnaireItemOperator.lessThanOrEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .integer,
            secondItemID: secondItemID,
            secondItemType: .integer,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Integer greater than or equal")
    func testIntegerGreaterThanOrEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .integer(100),
            operator: FHIRPrimitive(QuestionnaireItemOperator.greaterThanOrEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .integer,
            secondItemID: secondItemID,
            secondItemType: .integer,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
}


extension NavigationRulesTests {
    @Test("Decimal equal")
    func testDecimalEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .decimal(100.0),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .decimal,
            secondItemID: secondItemID,
            secondItemType: .decimal,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Decimal not equal")
    func testDecimalNotEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .decimal(100.0),
            operator: FHIRPrimitive(QuestionnaireItemOperator.notEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .decimal,
            secondItemID: secondItemID,
            secondItemType: .decimal,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Decimal greater than or equal")
    func testDecimalGreaterThanOrEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .decimal(100.0),
            operator: FHIRPrimitive(QuestionnaireItemOperator.greaterThanOrEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .decimal,
            secondItemID: secondItemID,
            secondItemType: .decimal,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Decimal less than or equal")
    func testDecimalLessThanOrEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .decimal(100.0),
            operator: FHIRPrimitive(QuestionnaireItemOperator.lessThanOrEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .decimal,
            secondItemID: secondItemID,
            secondItemType: .decimal,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Date less than")
    func testDateLessThan() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .date(FHIRPrimitive(try FHIRDate(date: Self.evaluationInstant))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.lessThan),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .date,
            secondItemID: secondItemID,
            secondItemType: .date,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Date greater than")
    func testDateGreaterThan() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .date(FHIRPrimitive(try FHIRDate(date: Self.evaluationInstant))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.greaterThan),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .date,
            secondItemID: secondItemID,
            secondItemType: .date,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Coding equal")
    func testCodingEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let coding = Coding(
            code: FHIRPrimitive(FHIRString("testCode")),
            system: FHIRPrimitive(FHIRURI("http://grovealliance.org/fhir/system/testSystem"))
        )
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .coding(coding),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .choice,
            secondItemID: secondItemID,
            secondItemType: .choice,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
    @Test("Coding not equal")
    func testCodingNotEqual() throws {
        let firstItemID = UUID().uuidString, secondItemID = UUID().uuidString
        let coding = Coding(
            code: FHIRPrimitive(FHIRString("testCode")),
            system: FHIRPrimitive(FHIRURI("http://grovealliance.org/fhir/system/testSystem"))
        )
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .coding(coding),
            operator: FHIRPrimitive(QuestionnaireItemOperator.notEqual),
            question: FHIRPrimitive(FHIRString(firstItemID))
        )
        let task = try createORKNavigableOrderedTask(
            firstItemID: firstItemID,
            firstItemType: .choice,
            secondItemID: secondItemID,
            secondItemType: .choice,
            enableWhen: enableWhen
        )
        #expect(task.skipNavigationRule(forStepIdentifier: secondItemID) != nil)
    }
}


extension FHIRToResearchKitTests {
    @Test("Malformed hidden items and nested duplicate linkIds fail global preflight")
    func globalPreflightIncludesHiddenAndNestedItems() throws {
        let hiddenURL = FHIRPrimitive(FHIRURI(
            stringLiteral: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
        ))
        let malformedHidden = QuestionnaireItem(
            extension: [Extension(url: hiddenURL, value: .boolean(FHIRPrimitive(true)))],
            linkId: "hidden".asFHIRStringPrimitive(),
            type: FHIRPrimitive<QuestionnaireItemType>()
        )
        let hiddenQuestionnaire = Questionnaire(
            item: [malformedHidden],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/Questionnaire/hidden")),
            version: "1.0.0".asFHIRStringPrimitive()
        )
        #expect(throws: FHIRToResearchKitConversionError.missingItemType(linkID: "hidden")) {
            try ORKNavigableOrderedTask(
                questionnaire: hiddenQuestionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }

        let duplicate = QuestionnaireItem(
            linkId: "same".asFHIRStringPrimitive(),
            text: "Question".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.string)
        )
        let nestedQuestionnaire = Questionnaire(
            item: [
                QuestionnaireItem(
                    item: [duplicate],
                    linkId: "group".asFHIRStringPrimitive(),
                    type: FHIRPrimitive(.group)
                ),
                duplicate
            ],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/Questionnaire/duplicates")),
            version: "1.0.0".asFHIRStringPrimitive()
        )
        #expect(throws: FHIRToResearchKitConversionError.duplicateLinkID("same")) {
            try ORKNavigableOrderedTask(
                questionnaire: nestedQuestionnaire,
                evaluationInstant: Self.evaluationInstant,
                evaluationTimeZone: Self.evaluationTimeZone
            )
        }
    }

    @Test("Valid hidden children are preflighted but not rendered in a visible form group")
    func hiddenGroupChildIsNotRendered() throws {
        let hiddenURL = FHIRPrimitive(FHIRURI(
            stringLiteral: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
        ))
        let questionnaire = Questionnaire(
            item: [
                QuestionnaireItem(
                    item: [
                        QuestionnaireItem(
                            extension: [Extension(url: hiddenURL, value: .boolean(FHIRPrimitive(true)))],
                            linkId: "hidden-child".asFHIRStringPrimitive(),
                            text: "Secret".asFHIRStringPrimitive(),
                            type: FHIRPrimitive(.string)
                        ),
                        QuestionnaireItem(
                            linkId: "visible-child".asFHIRStringPrimitive(),
                            text: "Visible".asFHIRStringPrimitive(),
                            type: FHIRPrimitive(.string)
                        )
                    ],
                    linkId: "group".asFHIRStringPrimitive(),
                    type: FHIRPrimitive(.group)
                )
            ],
            status: FHIRPrimitive(.active),
            url: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/fhir/Questionnaire/hidden-child")),
            version: "1.0.0".asFHIRStringPrimitive()
        )
        let task = try ORKNavigableOrderedTask(
            questionnaire: questionnaire,
            evaluationInstant: Self.evaluationInstant,
            evaluationTimeZone: Self.evaluationTimeZone
        )
        let form = try #require(task.steps.first as? ORKFormStep)
        #expect(form.formItems?.map { $0.identifier } == ["visible-child"])
    }
}


extension ResearchKitToFHIRTests {
    @Test("Response hierarchy mirrors Questionnaire groups")
    func groupHierarchyIsPreserved() throws {
        let child = QuestionnaireItem(
            linkId: "child".asFHIRStringPrimitive(),
            text: "Child".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.string)
        )
        let group = QuestionnaireItem(
            item: [child],
            linkId: "group".asFHIRStringPrimitive(),
            text: "Group".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.group)
        )
        let result = ORKTextQuestionResult(identifier: "child")
        result.textAnswer = "answer"
        let taskResult = createTaskResult(result)
        let response = try taskResult.fhirResponse(using: context(questionnaire: questionnaire(items: [group])))
        #expect(response.item?.map { $0.linkId.value?.string } == ["group"])
        #expect(response.item?.first?.item?.map { $0.linkId.value?.string } == ["child"])
        #expect(response.item?.first?.item?.first?.answer?.first?.value == .string("answer".asFHIRStringPrimitive()))
    }

    @Test("Children of a question are nested under its sole answer")
    func nestedQuestionHierarchyIsPreserved() throws {
        let child = QuestionnaireItem(
            linkId: "child".asFHIRStringPrimitive(),
            text: "Child".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.string)
        )
        let parent = QuestionnaireItem(
            item: [child],
            linkId: "parent".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Parent".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let parentResult = ORKChoiceQuestionResult(identifier: "parent")
        parentResult.choiceAnswers = ["yes" as any NSSecureCoding & NSCopying & NSObjectProtocol]
        let childResult = ORKTextQuestionResult(identifier: "child")
        childResult.textAnswer = "detail"
        let taskResult = ORKTaskResult(
            taskIdentifier: Self.questionnaireCanonical,
            taskRun: UUID(),
            outputDirectory: nil
        )
        taskResult.results = [createStepResult(parentResult), createStepResult(childResult)]
        let response = try taskResult.fhirResponse(using: context(questionnaire: questionnaire(items: [parent])))
        let nested = response.item?.first?.answer?.first?.item
        #expect(nested?.map { $0.linkId.value?.string } == ["child"])
        #expect(nested?.first?.answer?.first?.value == .string("detail".asFHIRStringPrimitive()))
        #expect(response.item?.first?.item == nil)
    }

    @Test("Nested children fail closed when multiple parent answers are ambiguous")
    func ambiguousNestedAnswersFail() throws {
        let child = QuestionnaireItem(
            linkId: "child".asFHIRStringPrimitive(),
            text: "Child".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.string)
        )
        let parent = QuestionnaireItem(
            item: [child],
            linkId: "parent".asFHIRStringPrimitive(),
            repeats: FHIRPrimitive(true),
            text: "Parent".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        let parentResult = ORKChoiceQuestionResult(identifier: "parent")
        parentResult.choiceAnswers = [
            "yes" as any NSSecureCoding & NSCopying & NSObjectProtocol,
            "no" as any NSSecureCoding & NSCopying & NSObjectProtocol
        ]
        let childResult = ORKTextQuestionResult(identifier: "child")
        childResult.textAnswer = "detail"
        let taskResult = ORKTaskResult(
            taskIdentifier: Self.questionnaireCanonical,
            taskRun: UUID(),
            outputDirectory: nil
        )
        taskResult.results = [createStepResult(parentResult), createStepResult(childResult)]
        #expect(throws: ResearchKitFHIRConversionError.ambiguousNestedResponse(linkID: "parent", answerCount: 2)) {
            try taskResult.fhirResponse(using: context(questionnaire: questionnaire(items: [parent])))
        }
    }

    @Test("Context rejects mismatched task identity and invalid author/source targets")
    func identityAndReferenceTargetsFailClosed() throws {
        let result = ORKTextQuestionResult(identifier: "testResult")
        result.textAnswer = "answer"
        let mismatched = ORKTaskResult(taskIdentifier: "wrong", taskRun: UUID(), outputDirectory: nil)
        mismatched.results = [createStepResult(result)]
        #expect(throws: ResearchKitFHIRConversionError.taskIdentifierMismatch(
            expected: Self.questionnaireCanonical,
            actual: "wrong"
        )) {
            try mismatched.fhirResponse(using: context())
        }
        let deviceID = try BusinessIdentifier(
            system: "https://example.org/fhir/identifier/device",
            value: "device-1"
        )
        let device = Reference(
            identifier: deviceID.fhirIdentifier,
            type: "Device".asFHIRURIPrimitive()
        )
        #expect(throws: ResearchKitFHIRConversionError.invalidReference(field: "source")) {
            try context(source: device)
        }
    }
}
