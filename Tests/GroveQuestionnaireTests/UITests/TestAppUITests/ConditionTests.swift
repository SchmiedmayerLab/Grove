//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


/// Questions that come and go as answers change, within a page and across pages.
final class ConditionTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testSimpleCondition() {
        launchAppAndStartExample("Simple Condition", in: .modelValues)
        XCTAssert(questionnaire.question("ice-cream").waitUntilAsked())
        XCTAssertFalse(questionnaire.question("ice-cream-flavor").isAsked)

        questionnaire.question("ice-cream").answer(true)
        XCTAssert(questionnaire.question("ice-cream-flavor").waitUntilAsked())

        questionnaire.question("ice-cream").answer(false)
        XCTAssert(questionnaire.question("ice-cream-flavor").waitUntilNoLongerAsked(timeout: 2))
    }


    @MainActor
    func testCrossSectionCondition() {
        launchAppAndStartExample("Cross-Section Condition", in: .modelValues)
        XCTAssert(questionnaire.question("ice-cream").waitUntilAsked())

        questionnaire.question("ice-cream").answer(false)
        questionnaire.advance()
        // the middle page has nothing left to ask, so it is passed over rather than shown empty
        XCTAssert(app.staticTexts["All Done!"].waitForExistence(timeout: 10))

        questionnaire.goBack()
        XCTAssert(app.staticTexts["All Done!"].waitForNonExistence(timeout: 10))

        questionnaire.question("ice-cream").answer(true)
        questionnaire.advance()

        XCTAssert(questionnaire.question("ice-cream-flavor").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        questionnaire.question("ice-cream-flavor").select("Mango")
        questionnaire.advance()
        XCTAssert(app.staticTexts["All Done!"].waitForExistence(timeout: 10))
    }


    /// A condition may only look backwards: section A gates on a *later* question and so never
    /// fires, section B gates on an earlier one and behaves.
    @MainActor
    func testConditionRules() {
        launchAppAndStartExample("Test Condition Lookup Rules", in: .modelValues)

        XCTAssert(app.staticTexts["Section A"].waitForExistence(timeout: 10))
        XCTAssert(questionnaire.question("t2A").waitUntilAsked())
        XCTAssertFalse(questionnaire.question("t1A").isAsked)
        questionnaire.question("t2A").select("Red")
        XCTAssert(questionnaire.question("t1A").waitUntilNoLongerAsked(timeout: 2))
        questionnaire.question("t2A").select("Green")
        XCTAssert(questionnaire.question("t1A").waitUntilAsked(timeout: 2))
        questionnaire.question("t2A").select("Blue")
        XCTAssert(questionnaire.question("t1A").waitUntilNoLongerAsked(timeout: 2))

        questionnaire.advance()
        XCTAssert(app.staticTexts["Section A"].waitForNonExistence(timeout: 2))
        XCTAssert(app.staticTexts["Section B"].waitForExistence(timeout: 10))
        XCTAssert(questionnaire.question("t1B").waitUntilAsked())

        XCTAssertFalse(questionnaire.question("t2B").isAsked)
        questionnaire.question("t1B").select("Red")
        XCTAssert(questionnaire.question("t2B").waitUntilNoLongerAsked(timeout: 2))
        questionnaire.question("t1B").select("Green")
        XCTAssert(questionnaire.question("t2B").waitUntilAsked(timeout: 2))
        questionnaire.question("t1B").deselect("Green")
        XCTAssert(questionnaire.question("t2B").waitUntilNoLongerAsked(timeout: 2))
        questionnaire.question("t1B").select("Green")
        XCTAssert(questionnaire.question("t2B").waitUntilAsked(timeout: 2))
        questionnaire.question("t1B").select("Blue")
        XCTAssert(questionnaire.question("t2B").waitUntilNoLongerAsked(timeout: 2))
    }


    /// A follow-up question can be gated on another follow-up of the same option.
    @MainActor
    func testConditionBetweenFollowUpQuestions() {
        launchAppAndStartExample("Nested Question with Inner-Reference Condition", in: .modelValues)
        XCTAssert(questionnaire.question("t0").waitUntilAsked())

        questionnaire.question("t0").select("Option 0") { followUp in
            XCTAssert(followUp.question("it0").waitUntilAsked())
            XCTAssertFalse(followUp.question("it1").isAsked)

            followUp.question("it0").answer(true)
            XCTAssert(followUp.question("it1").waitUntilAsked())

            followUp.question("it0").answer(false)
            XCTAssert(followUp.question("it1").waitUntilNoLongerAsked(timeout: 2))

            followUp.question("it0").answer(true)
            XCTAssert(followUp.question("it1").waitUntilAsked())
            XCTAssertEqual(followUp.offeredAction, .done)
            followUp.advance()
        }

        XCTAssert(questionnaire.question("it0").waitUntilNoLongerAsked())
        XCTAssert(questionnaire.question("t0").isSelected("Option 0"))
    }


    @MainActor
    func testFollowUpQuestionsSkippedIfNoneEnabled() {
        launchAppAndStartExample("Follow-Up Tasks Skipped if None Enabled", in: .modelValues)
        XCTAssert(questionnaire.question("t0").waitUntilAsked())

        // "Yes" enables the one follow-up, so selecting an option opens the follow-up page
        questionnaire.question("t0").answer(true)
        questionnaire.question("t1").select("Option 0") { followUp in
            XCTAssert(followUp.question("t1.1").waitUntilAsked())
            followUp.question("t1.1").answer(true)
            followUp.advance()
        }
        XCTAssert(questionnaire.question("t1.1").waitUntilNoLongerAsked())
        questionnaire.advance()

        XCTAssert(app.staticTexts["Section 2"].waitForExistence(timeout: 10))
        questionnaire.goBack()
        XCTAssert(app.staticTexts["Section 2"].waitForNonExistence(timeout: 10))
        XCTAssert(questionnaire.question("t0").waitUntilAsked())

        // "No" disables it, and with nothing left to ask the follow-up page is skipped outright
        questionnaire.question("t0").answer(false)
        questionnaire.advance()
        XCTAssert(app.staticTexts["Section 2"].waitForExistence(timeout: 10))
    }
}
