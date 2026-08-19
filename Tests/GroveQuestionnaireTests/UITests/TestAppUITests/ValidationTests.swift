//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


/// What the renderer does with an answer that is present but wrong.
///
/// All of it happens on the first page of the DSL's `Question Kinds` reference instrument, which
/// is where the modifiers that put rules on an answer are spelled out.
final class ValidationTests: TestAppUITests, @unchecked Sendable {
    private static let notAWebAddress = "Enter a web address, like https://example.org"

    /// The message names what the question is asking for, not the rule that rejected the answer.
    @MainActor
    func testFreeTextIsRejectedUntilItLooksLikeALink() throws {
        startQuestionKinds()

        questionnaire.question("website").enterText("example dot org")
        XCTAssert(questionnaire.question("website").showsText(Self.notAWebAddress))

        // FHIR regexes are anchored, so a path and a query have to be accepted along with the host
        try questionnaire.question("website").clearText()
        questionnaire.question("website").enterText("https://github.com/test")
        XCTAssertFalse(questionnaire.question("website").showsText(Self.notAWebAddress))
    }


    @MainActor
    func testFreeTextIsRejectedUntilItIsLongEnough() {
        startQuestionKinds()

        questionnaire.question("about").enterText("ab")
        XCTAssert(questionnaire.question("about").showsText("Length must be between 3 and 280"))

        questionnaire.question("about").enterText("cde")
        XCTAssertFalse(questionnaire.question("about").showsText("Length must be between 3 and 280"))
    }


    /// Optional means the participant may leave it blank, not that anything goes in it.
    @MainActor
    func testAnInvalidAnswerBlocksThePageEvenWhenTheQuestionIsOptional() throws {
        startQuestionKinds()

        // everything the page requires, so that the optional question is the only thing left to object
        questionnaire.question("flavour").select("Strawberry")
        questionnaire.question("continent").chooseFromMenu("Europe")
        questionnaire.question("agrees").answer(true)
        questionnaire.question("about").enterText("Nothing much to tell.")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))

        questionnaire.question("website").enterText("example dot org")
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        // the answer is what is wrong, so the page says so under the question rather than asking for one
        XCTAssert(questionnaire.question("website").showsText(Self.notAWebAddress))
        XCTAssertFalse(questionnaire.question("website").isMarkedAsBlocking)

        try questionnaire.question("website").clearText()
        // blank is an answer this question accepts, so the page stops objecting
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertFalse(questionnaire.question("website").showsText(Self.notAWebAddress))
    }


    @MainActor
    private func startQuestionKinds() {
        launchAppAndStartExample("Question Kinds", in: .swiftDSL)
        XCTAssert(questionnaire.question("flavour").waitUntilAsked())
    }
}
