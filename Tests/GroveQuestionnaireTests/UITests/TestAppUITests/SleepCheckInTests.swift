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


/// Covers the Swift-DSL showcase instrument: group-level gating, a follow-up keyed on a typed
/// option, and a score computed from the option weights.
final class SleepCheckInTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testGroupConditionGatesEveryQuestionInside() {
        launchAndStartSleepCheckIn()

        // Nothing is answered yet, so neither branch of the boolean is asked.
        XCTAssertFalse(questionnaire.question("falling-asleep").isAsked)
        XCTAssertFalse(questionnaire.question("waking-up").isAsked)
        XCTAssertFalse(questionnaire.question("daytime-tiredness").isAsked)
        XCTAssertFalse(questionnaire.question("slept-well").isAsked)
        XCTAssertFalse(questionnaire.showsText("Recent nights"))

        questionnaire.question("sleep-trouble").answer(false)
        XCTAssert(questionnaire.question("slept-well").waitUntilAsked())
        XCTAssertFalse(questionnaire.question("falling-asleep").isAsked)
        XCTAssertFalse(questionnaire.question("waking-up").isAsked)
        XCTAssertFalse(questionnaire.question("daytime-tiredness").isAsked)
        // the group's heading goes with the questions inside it
        XCTAssertFalse(questionnaire.showsText("Recent nights"))

        questionnaire.question("sleep-trouble").answer(true)
        XCTAssert(questionnaire.question("falling-asleep").waitUntilAsked())
        XCTAssert(questionnaire.question("waking-up").isAsked)
        XCTAssert(questionnaire.question("daytime-tiredness").isAsked)
        XCTAssert(questionnaire.showsText("Recent nights"))
        XCTAssert(questionnaire.question("slept-well").waitUntilNoLongerAsked(timeout: 2))
    }


    @MainActor
    func testTypedOptionFollowUp() {
        launchAndStartSleepCheckIn()
        questionnaire.question("sleep-trouble").answer(false)
        questionnaire.advance()

        XCTAssert(questionnaire.question("evening-drink").waitUntilAsked())
        XCTAssert(questionnaire.sectionIntro.wait(for: \.label, toEqual: "Evening Habits", timeout: 10))
        XCTAssertFalse(questionnaire.question("drink-details").isAsked)

        questionnaire.question("evening-drink").select("Something caffeinated")
        XCTAssert(questionnaire.question("drink-details").waitUntilAsked())

        // The follow-up belongs to one case of the option set, not to the question.
        questionnaire.question("evening-drink").select("Alcohol")
        XCTAssert(questionnaire.question("drink-details").waitUntilNoLongerAsked(timeout: 2))
    }


    @MainActor
    func testComputedScoreFollowsTheOptionWeights() throws {
        launchAndStartSleepCheckIn()
        questionnaire.question("sleep-trouble").answer(true)
        XCTAssert(questionnaire.question("falling-asleep").waitUntilAsked())

        questionnaire.question("falling-asleep").select("Some nights") // 1
        questionnaire.question("waking-up").select("Most nights") // 2
        questionnaire.question("daytime-tiredness").select("Every night") // 3

        // The advisory is gated on the score, so its presence is the score being read back.
        XCTAssert(questionnaire.question("advisory").waitUntilAsked())
        XCTAssertEqual(questionnaire.question("sleep-score").fieldValue, "6")

        questionnaire.advance()
        XCTAssert(questionnaire.question("evening-drink").waitUntilAsked())
        questionnaire.question("evening-drink").select("Nothing")
        try questionnaire.question("screen-minutes").enterNumber(30)

        questionnaire.submit()
        XCTAssert(questionnaire.waitUntilAtCompletionPage())
        questionnaire.finish()
        XCTAssert(questionnaire.waitUntilDismissed())

        assertResponseWasCollected(from: "Sleep Check-In")
    }


    @MainActor
    private func launchAndStartSleepCheckIn() {
        launchAppAndStartExample("Sleep Check-In", in: .swiftDSL)
        XCTAssert(questionnaire.question("sleep-trouble").waitUntilAsked())
    }
}
