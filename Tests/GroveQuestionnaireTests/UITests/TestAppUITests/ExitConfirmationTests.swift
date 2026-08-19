//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


/// What the Close button costs, and what it offers instead of costing it.
final class ExitConfirmationTests: TestAppUITests, @unchecked Sendable {
    /// Nothing has been entered, so there is nothing to warn about.
    @MainActor
    func testClosingAnUntouchedQuestionnaireAsksNothing() {
        launchAppAndStartExample("Simple Condition", in: .modelValues)
        XCTAssert(questionnaire.question("ice-cream").waitUntilAsked())

        questionnaire.close()
        XCTAssert(questionnaire.waitUntilDismissed())
        returnToRootPage()
        XCTAssert(app.staticTexts["Completed, 0"].exists)
    }


    @MainActor
    func testKeepAnsweringReturnsToThePageWithTheAnswersIntact() throws {
        launchAppAndStartExample("Simple Number Entry", in: .modelValues)
        try questionnaire.question("t0").enterNumber(5)

        questionnaire.closeButton.tap()
        XCTAssert(questionnaire.exitOption(.discardAnswers).waitForExistence(timeout: 10))
        // a half-answered questionnaire has answers to lose, but none to hand off
        XCTAssertFalse(questionnaire.exitOption(.submitAnswers).exists)
        questionnaire.keepAnswering()

        XCTAssertFalse(questionnaire.isShowingExitConfirmation)
        XCTAssert(questionnaire.isPresented)
        XCTAssertEqual(questionnaire.question("t0").fieldValue, "5")
    }


    @MainActor
    func testDiscardingLeavesWithoutRecordingAnything() throws {
        launchAppAndStartExample("Simple Number Entry", in: .modelValues)
        try questionnaire.question("t0").enterNumber(5)

        questionnaire.close(choosing: .discardAnswers)
        XCTAssert(questionnaire.waitUntilDismissed())
        returnToRootPage()
        XCTAssert(app.staticTexts["Completed, 0"].exists)
    }


    /// Someone deliberately leaving a finished questionnaire should not be handed one more screen.
    ///
    /// This is also the questionnaire's other way of handing answers off: the dialog is gone the
    /// instant its button is tapped, so the page keeps the work and reports through its own state.
    @MainActor
    func testClosingAFinishedQuestionnaireOffersToSubmitInstead() {
        launchApp()
        open(.completionFlow)
        startExample("Completion Page, Submit", titled: "Reopenable Survey")
        questionnaire.question("flavour").select("Strawberry")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))

        questionnaire.closeButton.tap()
        XCTAssert(questionnaire.exitOption(.submitAnswers).waitForExistence(timeout: 10))
        XCTAssert(questionnaire.exitOption(.discardAnswers).exists)
        questionnaire.exitOption(.submitAnswers).tap()

        // the answers go straight to the app, without the completion page this example enables
        XCTAssert(questionnaire.waitUntilDismissed())
        XCTAssertFalse(questionnaire.isAtCompletionPage)
        assertResponseWasCollected(from: "Completion Page, Submit")
    }


    /// Leaving a follow-up page undoes the selection that opened it.
    @MainActor
    func testClosingAFollowUpPageDeselectsTheOptionItBelongsTo() {
        launchAppAndStartExample("Follow-Up Tasks Skipped if None Enabled", in: .modelValues)
        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        questionnaire.question("t0").answer(true)

        questionnaire.question("t1").select("Option 0") { followUp in
            XCTAssert(followUp.question("t1.1").waitUntilAsked())
            followUp.question("t1.1").answer(true)
            followUp.close(choosing: .discardAnswers)
        }

        XCTAssert(questionnaire.question("t1.1").waitUntilNoLongerAsked())
        XCTAssertFalse(questionnaire.question("t1").isSelected("Option 0"))
        // the questionnaire itself is untouched; only the follow-ups were discarded
        XCTAssert(questionnaire.isPresented)
        XCTAssert(questionnaire.question("t0").isSelected("Yes"))
    }
}
