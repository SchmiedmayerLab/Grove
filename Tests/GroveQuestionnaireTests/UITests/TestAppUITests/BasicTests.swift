//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveQuestionnaire


final class BasicTests: TestAppUITests, @unchecked Sendable {
    /// One run end to end, driven through the raw identifiers rather than through the navigator.
    ///
    /// It is the contract test for the identifiers ``QuestionnaireSheetNavigator`` is built on:
    /// if this one breaks, everything written against the helper breaks with it.
    @MainActor
    func testGroveQuestionnaire() {
        launchApp()
        XCTAssert(app.staticTexts["Authoring"].exists)
        XCTAssert(app.staticTexts["Completed, 0"].exists)

        open(.fhir)
        startFHIRExample("Glasgow Coma Score")

        // An option is one element, labelled with its title and its selection state: the row
        // ignores its own children so that VoiceOver reads "Confused, Not Selected" and not
        // the checkmark beside it.
        tap(app.otherElements["Task:1.1"].buttons["Option: Confused, Not Selected"])
        XCTAssert(app.otherElements["Task:1.1"].buttons["Option: Confused, Selected"].waitForExistence(timeout: 10))
        tap(app.otherElements["Task:1.2"].buttons["Option: Obeys commands, Not Selected"])
        tap(app.otherElements["Task:1.3"].buttons["Option: Eye opening to verbal command, Not Selected"])

        // the action is the page's last row, so a page this long has to be scrolled to reach it
        questionnaire.scrollToPrimaryAction()
        let primaryAction = app.buttons.matching(identifier: "PrimaryAction").allElementsBoundByIndex.last
        XCTAssertEqual(primaryAction?.label, "Submit")
        XCTAssertEqual(primaryAction?.value as? String, "Ready")
        // this example asks for no completion page, so submitting hands the answers straight over
        primaryAction?.tap()
        XCTAssert(questionnaire.waitUntilDismissed())

        assertResponseWasCollected(from: "Glasgow Coma Score")
    }


    /// The same run, said through ``QuestionnaireSheetNavigator``.
    @MainActor
    func testTheSameRunThroughTheNavigator() {
        launchAppAndStartFHIRExample("Glasgow Coma Score")

        XCTAssert(questionnaire.question("1.1").waitUntilAsked())
        questionnaire.question("1.1").select("Confused")
        questionnaire.question("1.2").select("Obeys commands")
        questionnaire.question("1.3").select("Eye opening to verbal command")
        XCTAssert(questionnaire.question("1.3").isSelected("Eye opening to verbal command"))

        // No completion page here, so submitting hands the answers straight to the app; the page
        // itself is exercised by the Completion Flow examples, which ask for one.
        XCTAssertEqual(questionnaire.offeredAction, .submit)
        questionnaire.submit()
        XCTAssert(questionnaire.waitUntilDismissed())

        assertResponseWasCollected(from: "Glasgow Coma Score")
    }


    /// Nothing on the Glasgow Coma Score is required, so the page is ready before it is answered.
    @MainActor
    func testOptionalQuestionsNeverBlockAPage() {
        launchAppAndStartFHIRExample("Glasgow Coma Score")

        XCTAssert(questionnaire.question("1.1").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertFalse(questionnaire.question("1.1").isMarkedAsBlocking)

        // and tapping through leaves the unanswered questions unanswered rather than objecting
        questionnaire.advance()
        XCTAssert(questionnaire.waitUntilDismissed())
    }


    @MainActor
    func testSimpleNumberEntry() throws {
        launchAppAndStartExample("Simple Number Entry", in: .modelValues)
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))

        try questionnaire.question("t0").enterNumber(5)
        XCTAssertFalse(questionnaire.isReadyToAdvance)
        try questionnaire.question("t1").enterNumber(7)
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertEqual(questionnaire.question("t0").fieldValue, "5")
        XCTAssertEqual(questionnaire.question("t1").fieldValue, "7")
    }


    /// The sheet does not have to own its responses: answered once, the same object reopens with the answer in place.
    @MainActor
    func testExistingResponsesObject() {
        launchApp()
        open(.existingResponses)

        let answerButton = app.buttons["AnswerQuestionnaire"]
        let reopenButton = app.buttons["ReopenQuestionnaire"]
        XCTAssert(answerButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssert(answerButton.isEnabled)
        XCTAssert(reopenButton.exists)
        XCTAssertFalse(reopenButton.isEnabled)

        answerButton.tap()
        XCTAssert(questionnaire.question("flavour").waitUntilAsked())
        XCTAssertFalse(questionnaire.question("flavour").isSelected("Strawberry"))
        XCTAssertFalse(questionnaire.question("flavour").isSelected("Mango"))

        questionnaire.question("flavour").select("Mango")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertTrue(questionnaire.question("flavour").isSelected("Mango"))
        XCTAssertFalse(questionnaire.question("flavour").isSelected("Strawberry"))

        // this example turns the completion page off, so the primary action hands the answers straight back
        XCTAssertEqual(questionnaire.offeredAction, .submit)
        questionnaire.submit()
        XCTAssert(questionnaire.waitUntilDismissed())
        XCTAssertFalse(questionnaire.isAtCompletionPage)

        // the answers outlived the sheet, so the page can show them and hand them back to a second one
        XCTAssert(app.staticTexts["Held Answers"].waitForExistence(timeout: 10))
        // a labelled row reads as one element, so the answer is part of what it says rather than a text of its own
        let heldFlavour = app.descendants(matching: .any).matching(identifier: "HeldAnswer:flavour").firstMatch
        XCTAssert(heldFlavour.exists)
        XCTAssert(heldFlavour.label.contains("Mango"))
        XCTAssert(reopenButton.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        XCTAssert(answerButton.isEnabled)
        reopenButton.tap()

        XCTAssert(questionnaire.question("flavour").waitUntilAsked())
        XCTAssertTrue(questionnaire.question("flavour").isSelected("Mango"))
        XCTAssertFalse(questionnaire.question("flavour").isSelected("Strawberry"))
        // reopened for review rather than for handing off, so the last button says so
        XCTAssertEqual(questionnaire.offeredAction, .done)
    }
}
