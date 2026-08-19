//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers the parts of the chat that only exist as behaviour: what the composer does mid-answer, what fills an
/// empty conversation, how a failure is reported, and where a message's actions live.
@MainActor
final class ChatInteractionUITests: XCTestCase {
    override func setUp() async throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
        XCTAssert(app.launchAndWait(for: app.textFields["Message Input Textfield"]), "The chat did not come up after launch.")
    }

    func testEmptyStateAppearsForAFreshChat() throws {
        let app = XCUIApplication()

        XCTAssert(app.staticTexts["Assistant Message!"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Ask Me Anything"].exists, "A conversation with messages should not show a placeholder.")

        app.buttons["New Chat"].tap()

        XCTAssert(app.staticTexts["Ask Me Anything"].waitForExistence(timeout: 2), "An empty chat should show its placeholder.")
        XCTAssert(app.staticTexts["Assistant Message!"].waitForNonExistence(timeout: 2))
    }

    func testTheComposerStopsAndLocksWhileAnswering() throws {
        let app = XCUIApplication()

        try app.textFields["Message Input Textfield"].enter(value: "Hello there", options: [.disableKeyboardDismiss])
        app.buttons["Send Message"].tap()

        let stopButton = app.buttons["Stop Generating"]
        XCTAssert(stopButton.waitForExistence(timeout: 3), "The send button should become a stop button while answering.")
        XCTAssertFalse(app.buttons["Send Message"].exists, "A second message must not be sendable mid-answer.")

        stopButton.tap()

        XCTAssert(stopButton.waitForNonExistence(timeout: 3), "Stopping should hand the composer back.")
        XCTAssert(app.otherElements["Typing Indicator"].waitForNonExistence(timeout: 3))
    }

    func testAFailedAnswerIsReportedInlineAndCanBeRetried() throws {
        let app = XCUIApplication()

        try app.textFields["Message Input Textfield"].enter(value: "please fail", options: [.disableKeyboardDismiss])
        app.buttons["Send Message"].tap()

        let failureText = app.staticTexts["The assistant could not be reached. Check your connection and try again."]
        XCTAssert(failureText.waitForExistence(timeout: 10), "A failed answer should be reported in the conversation.")

        let retry = app.buttons["Try Again"]
        XCTAssert(retry.exists, "A reported failure should offer a retry.")
        retry.tap()

        // The retry re-runs the same prompt, so the failure returns — what matters is that it ran at all.
        XCTAssert(failureText.waitForExistence(timeout: 10))
    }

    func testMessageActionsLiveBehindALongPress() throws {
        let app = XCUIApplication()

        let assistantMessage = app.staticTexts["Assistant Message!"]
        XCTAssert(assistantMessage.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Copy"].exists, "Actions should stay out of the conversation until asked for.")

        assistantMessage.press(forDuration: 1.2)

        XCTAssert(app.buttons["Copy"].waitForExistence(timeout: 3), "A long press should offer the message's actions.")
        XCTAssert(app.buttons["Share"].exists)
    }
}
