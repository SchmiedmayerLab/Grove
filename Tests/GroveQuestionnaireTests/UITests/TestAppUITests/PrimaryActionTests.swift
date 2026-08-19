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


/// The one button at the bottom of a section page: where it sits, what it says, and what it does
/// when the page is not answered yet.
final class PrimaryActionTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testTheButtonNamesTheStepItTakes() {
        launchAppAndStartExample("Cross-Section Condition", in: .modelValues)
        XCTAssert(questionnaire.question("ice-cream").waitUntilAsked())

        // more pages to come, and nothing answered yet
        XCTAssertEqual(questionnaire.offeredAction, .continue)
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        // the button stays enabled while the page is unfinished, because it is what explains why
        XCTAssert(questionnaire.primaryAction.isEnabled)

        questionnaire.question("ice-cream").answer(false)
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertEqual(questionnaire.offeredAction, .continue)

        // answering "No" empties the middle page, so the next one is the last
        questionnaire.advance()
        XCTAssert(app.staticTexts["All Done!"].waitForExistence(timeout: 10))
        XCTAssert(questionnaire.waitUntilOffering(.submit))
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
    }


    /// The button ends the page rather than covering it: the participant arrives at it by
    /// finishing the questions, and nothing of the page is left underneath it.
    @MainActor
    func testTheButtonEndsThePage() {
        launchAppAndStartExample("Patient Health Questionnaire-9", in: .modelValues)
        XCTAssert(questionnaire.question("H1/T1/Q1").waitUntilAsked())

        // a page this long opens with the button still below the fold
        XCTAssertFalse(questionnaire.primaryAction.isHittable)
        XCTAssert(questionnaire.scrollToPrimaryAction())

        let button = questionnaire.primaryAction
        XCTAssertGreaterThan(button.frame.minY, questionnaire.question("H1/T1/Q9").element.frame.maxY)
        // the foot of the page, so scrolling on cannot take the button anywhere
        let restingFrame = button.frame
        questionnaire.scrollDown()
        XCTAssertEqual(button.frame, restingFrame)
    }


    /// A consumer editing a record it can reopen asks for `Done`; the completion page's button always reads that way.
    @MainActor
    func testDoneReplacesSubmitWhenNothingIsHandedOff() {
        launchApp()
        open(.completionFlow)
        startExample("Completion Page, Done", titled: "Reopenable Survey")

        XCTAssertEqual(questionnaire.offeredAction, .done)
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        questionnaire.question("flavour").select("Strawberry")
        questionnaire.submit()

        XCTAssert(questionnaire.waitUntilAtCompletionPage())
        XCTAssertEqual(questionnaire.offeredAction, .done)
        XCTAssertEqual(questionnaire.readiness, .ready)
        // the completion page is the hand-off, so it offers no way back and no way out
        XCTAssertFalse(questionnaire.closeButton.isHittable)
        questionnaire.finish()

        XCTAssert(questionnaire.waitUntilDismissed())
        assertResponseWasCollected(from: "Completion Page, Done")
    }


    @MainActor
    func testSubmittingWithoutACompletionPage() {
        launchApp()
        open(.completionFlow)
        startExample("No Completion Page", titled: "Reopenable Survey")

        questionnaire.question("flavour").select("Mango")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertEqual(questionnaire.offeredAction, .submit)
        questionnaire.submit()

        // the responses go straight to the consumer, with no page in between
        XCTAssert(questionnaire.waitUntilDismissed())
        XCTAssertFalse(questionnaire.isAtCompletionPage)
        assertResponseWasCollected(from: "No Completion Page")
    }


    /// Tapping the button on an unanswered page answers the tap: it marks everything that blocks
    /// the page, and brings the first of it back into view.
    @MainActor
    func testAnIncompletePageMarksEveryQuestionThatBlocksIt() {
        launchAppAndStartExample("GAD-7 Anxiety", in: .modelValues)
        XCTAssert(questionnaire.question("q1").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        XCTAssertFalse(questionnaire.question("q1").isMarkedAsBlocking)

        // scroll the blocking questions out of sight, so the tap has somewhere to bring them back from
        questionnaire.scrollDown()
        questionnaire.scrollDown()
        XCTAssertFalse(questionnaire.question("q1").option("Not at all").isHittable)

        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("q1").option("Not at all").wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssert(questionnaire.question("q1").blockingMark.waitForExistence(timeout: 10))
        // every question that blocks is marked, not only the one that was scrolled to
        XCTAssert(questionnaire.question("q2").isMarkedAsBlocking)
        XCTAssertFalse(questionnaire.isAtCompletionPage)

        // answering clears that question's mark, and leaves the rest of them alone
        questionnaire.question("q1").select("Not at all")
        XCTAssert(questionnaire.question("q1").blockingMark.waitForNonExistence(timeout: 5))
        XCTAssert(questionnaire.question("q2").isMarkedAsBlocking)

        for question in ["q2", "q3", "q4", "q5", "q6", "q7"] {
            questionnaire.question(question).select("Not at all")
        }
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        questionnaire.submit()
        XCTAssert(questionnaire.waitUntilDismissed())
    }


    /// The marks belong to the page that earned them; the next one starts clean.
    @MainActor
    func testMovingOnClearsTheMarks() {
        launchAppAndStartExample("Cross-Section Condition", in: .modelValues)
        XCTAssert(questionnaire.question("ice-cream").waitUntilAsked())

        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("ice-cream").blockingMark.waitForExistence(timeout: 10))
        questionnaire.question("ice-cream").answer(true)
        XCTAssert(questionnaire.question("ice-cream").blockingMark.waitForNonExistence(timeout: 5))
        questionnaire.advance()

        XCTAssert(questionnaire.question("ice-cream-flavor").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        XCTAssertFalse(questionnaire.question("ice-cream-flavor").isMarkedAsBlocking)
        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("ice-cream-flavor").blockingMark.waitForExistence(timeout: 10))
    }
}
