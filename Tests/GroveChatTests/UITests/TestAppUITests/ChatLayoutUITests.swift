//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers where the conversation sits and how wide its messages are — what a reader notices before they
/// read anything.
@MainActor
final class ChatLayoutUITests: XCTestCase {
    private var app: XCUIApplication { XCUIApplication() }
    private var composer: XCUIElement { app.textFields["Message Input Textfield"] }

    override func setUp() {
        continueAfterFailure = false
    }

    /// A conversation shorter than the screen reads from the top. Aligning it to the bottom instead left the
    /// first message hovering just above the composer with the whole page empty above it.
    func testAShortConversationStartsAtTheTopOfThePage() throws {
        let app = launch(startingEmpty: true)
        try send("Hi", in: app)
        XCTAssert(
            app.staticTexts["**Assistant** Message Response!"].waitForExistence(timeout: 20) ||
                app.staticTexts["Assistant Message Response!"].waitForExistence(timeout: 5),
            "The mocked assistant should have answered."
        )

        let scrollView = app.scrollViews.firstMatch
        XCTAssert(scrollView.exists)
        XCTAssertLessThan(
            app.staticTexts["Hi"].frame.minY,
            scrollView.frame.minY + scrollView.frame.height / 3,
            "A two-message conversation should begin near the top, leaving the empty space below it."
        )
    }

    /// A text-only message is as wide as its text. Stretching it to the full content width and centring the
    /// text inside made every one-word answer look like a paragraph.
    func testAUserMessageIsOnlyAsWideAsItsText() throws {
        let app = launch(startingEmpty: true)
        try send("Hi", in: app)

        let bubble = app.staticTexts["Hi"]
        XCTAssert(bubble.waitForExistence(timeout: 10), "The message the user sent should be in the conversation.")
        XCTAssertLessThan(
            bubble.frame.width,
            app.windows.firstMatch.frame.width / 2,
            "A two-letter message should not claim half the width of the screen."
        )
    }

    /// Input an app primed the model with is a real user turn, so only its identity can keep it out of the
    /// conversation. Everything else on the page still renders.
    func testAMessageTheAppNamedAsHiddenIsNotShown() throws {
        let app = launch(hidingInternalInput: true)

        XCTAssert(
            app.staticTexts["What do you make of this?"].waitForExistence(timeout: 10),
            "The participant's own message stays visible."
        )
        XCTAssertFalse(
            app.staticTexts["Follow the instructions to begin."].exists,
            "A message the app named as hidden should never reach the participant."
        )
    }

    private func launch(startingEmpty: Bool = false, hidingInternalInput: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
            + (startingEmpty ? ["--emptyChat"] : [])
            + (hidingInternalInput ? ["--hideInternalInput"] : [])
        XCTAssert(app.launchAndWait(for: composer), "The chat did not come up after launch.")
        return app
    }

    private func send(_ message: String, in app: XCUIApplication) throws {
        XCTAssert(composer.wait(for: \.isHittable, toEqual: true, timeout: 5))
        try composer.enter(value: message, options: [.disableKeyboardDismiss])
        let send = app.buttons["Send Message"]
        XCTAssert(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
        send.tap()
    }
}
