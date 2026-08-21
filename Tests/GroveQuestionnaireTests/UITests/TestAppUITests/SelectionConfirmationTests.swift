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


/// Covers the beat between answering a question and the page moving on to the next one.
final class SelectionConfirmationTests: TestAppUITests, @unchecked Sendable {
    /// An answer used to scroll away in the frame it was given in, so nothing was ever seen to be
    /// accepted. The mark now has time to arrive, and it is still there once the page has moved on.
    @MainActor
    func testAnAnsweredQuestionStaysAnsweredAsThePageMovesOn() {
        launchAppAndStartFHIRExample("Glasgow Coma Score")

        XCTAssert(questionnaire.question("1.1").waitUntilAsked())
        questionnaire.question("1.1").select("Confused")
        XCTAssert(
            questionnaire.question("1.1").isSelected("Confused"),
            "An answer has to be confirmed on the question it was given on."
        )

        // Moving on is what the confirmation delays, not what it replaces.
        XCTAssert(questionnaire.question("1.2").waitUntilAsked())
        questionnaire.question("1.2").select("Obeys commands")
        XCTAssert(questionnaire.question("1.2").isSelected("Obeys commands"))
        XCTAssert(
            questionnaire.question("1.1").isSelected("Confused"),
            "Answering the next question has to leave the one before it alone."
        )
    }

    /// Clearing an answer is not progress, so it leaves the participant on the question they cleared.
    @MainActor
    func testClearingAnAnswerLeavesTheParticipantOnTheQuestion() {
        launchAppAndStartFHIRExample("Glasgow Coma Score")

        XCTAssert(questionnaire.question("1.1").waitUntilAsked())
        questionnaire.question("1.1").select("Confused")
        questionnaire.question("1.1").deselect("Confused")

        XCTAssertFalse(questionnaire.question("1.1").isSelected("Confused"))
        XCTAssert(questionnaire.question("1.1").isAsked, "Clearing an answer should not move the page.")
    }
}
