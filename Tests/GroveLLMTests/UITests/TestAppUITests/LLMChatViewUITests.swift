//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers what ``LLMChatView`` publishes into the chat it presents.
///
/// The composer draws its stop button, its failure banner and its attach menu from environment state, and only the
/// view that owns the session can supply it. That link is not reachable from a unit test — it was missing entirely
/// at one point, so the stop button existed but could never appear — which is what these tests hold in place.
///
/// Everything runs against ``LLMMockSession``, so no provider is involved and nothing is billed.
@MainActor
final class LLMChatViewUITests: TestAppTestCase {
    func testTheStopButtonAppearsWhileGeneratingAndStopsIt() throws {
        try openMockChat()
        try send("Hello")

        let stop = app.buttons["Stop Generating"]
        XCTAssert(stop.waitForExistence(timeout: 10), "A session that is working has to offer a way to stop it.")
        stop.tap()

        XCTAssert(stop.waitForNonExistence(timeout: 15), "Stopping has to end the generation, not just hide the button.")
        // An idle composer offers dictation where the stop button was; Send only appears once there is text to send.
        XCTAssert(app.buttons["Record Message"].waitForExistence(timeout: 10), "The composer returns once it is idle.")
    }

    func testAnIdleChatOffersNoStopButton() throws {
        try openMockChat()

        XCTAssertFalse(app.buttons["Stop Generating"].exists, "Nothing is generating, so nothing should offer to stop it.")
        XCTAssert(app.textFields["Message Input Textfield"].waitForExistence(timeout: 10))
    }

    func testAFailureIsShownInlineAndCanBeRetried() throws {
        try openMockChat()
        try send("Hello")

        // Let the answer land, so the retry re-runs a finished turn rather than racing the first one.
        XCTAssert(app.buttons["Stop Generating"].waitForNonExistence(timeout: 25))

        app.buttons["Force Error"].tap()

        let retry = app.buttons["Try Again"]
        XCTAssert(retry.waitForExistence(timeout: 10), "A failed turn has to say so in the conversation.")
        retry.tap()

        XCTAssert(retry.waitForNonExistence(timeout: 15), "Retrying clears the failure and asks again.")
    }

    func testAFailureThatCannotImproveIsNotOfferedARetry() throws {
        try openMockChat()

        app.buttons["Force Fatal Error"].tap()

        // The failure is still reported — it is the button that would not work that is withheld.
        XCTAssert(
            app.staticTexts["The mock session was asked to fail permanently."].waitForExistence(timeout: 10),
            "A permanent failure still has to be shown."
        )
        XCTAssertFalse(app.buttons["Try Again"].exists, "Retrying cannot help, so it must not be offered.")
        // With no button to offer, the way out is the only thing left worth showing.
        XCTAssert(
            app.staticTexts["Nothing here can fix it; the app has to."].exists,
            "A failure with no retry has to say what would actually help."
        )
    }

    func testTheAttachMenuOffersOnlyTheConfiguredKinds() throws {
        try openMockChat()

        let attach = app.buttons["Add Attachment"]
        XCTAssert(attach.waitForExistence(timeout: 10), "The chat was configured with attachments, so the button belongs there.")
        attach.tap()

        XCTAssert(app.buttons["Photo Library"].waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Choose Files"].exists)
        XCTAssertFalse(app.buttons["Take Photo"].exists, "The camera was not among the configured kinds.")
    }

    /// Asserts the whole answer under one label on purpose: a completion racing the delta consumer once
    /// split a streamed message in two, which a joined-labels assertion would have hidden.
    func testTheStreamedAnswerIsShown() throws {
        try openMockChat()
        try send("Hello")

        XCTAssert(
            app.staticTexts["Mock Message from GroveLLM!"].waitForExistence(timeout: 20),
            "The streamed answer should be rendered as one message, reachable through accessibility."
        )
    }

    /// The instant stream lands the answer within the conversation's first frames — the timing under which
    /// a lazily materialized first row once missed its appear events and rendered as nothing.
    func testAnOpeningAnswerToAHiddenInputIsShown() throws {
        try openMockChat(extraArguments: ["--hiddenStarter", "--instantMockStream"])

        XCTAssert(
            app.staticTexts["Mock Message from GroveLLM!"].waitForExistence(timeout: 20),
            "The answer to the hidden opening input should be the conversation's first visible message."
        )
        XCTAssertFalse(
            app.staticTexts["Follow the instructions to begin."].exists,
            "The internal opening input is not the participant's message."
        )
    }

    private func openMockChat(extraArguments: [String] = []) throws {
        launch(enableMockMode: true, showOnboarding: false, clearAPIKeysFromKeychain: false)
        if !extraArguments.isEmpty {
            app.terminate()
            app.launchArguments += extraArguments
            app.launch()
        }
        let entry = app.collectionViews.buttons["LLMMock Chat"].firstMatch
        XCTAssert(entry.waitForExistence(timeout: 10), "The mock chat has to be reachable from the test app.")
        entry.tap()
    }

    private func send(_ message: String) throws {
        let composer = app.textFields["Message Input Textfield"]
        XCTAssert(composer.wait(for: \.isHittable, toEqual: true, timeout: 10))
        try composer.enter(value: message, options: [.disableKeyboardDismiss])
        let send = app.buttons["Send Message"]
        XCTAssert(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
        send.tap()
    }
}
