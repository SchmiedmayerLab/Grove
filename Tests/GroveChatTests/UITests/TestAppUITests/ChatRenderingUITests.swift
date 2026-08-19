//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers how each kind of message the chat supports actually renders.
///
/// Everything here runs against the test app's mocked assistant, so the coverage is of the chat's own rendering
/// rather than of any provider: a reasoning summary folded into a disclosure, an image, a Markdown table, a fenced
/// code block, and a tool call with its response.
@MainActor
final class ChatRenderingUITests: XCTestCase {
    override func setUp() async throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
        XCTAssert(app.launchAndWait(for: app.textFields["Message Input Textfield"]), "The chat did not come up after launch.")
    }

    func testAReasoningSummaryIsFoldedIntoADisclosure() throws {
        let app = XCUIApplication()
        try send("think about it", in: app)

        // While the phase runs the disclosure counts up; once it finishes it says how long it took.
        let thinking = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Thought for")).firstMatch
        XCTAssert(thinking.waitForExistence(timeout: 20), "A finished thinking phase should offer its summary.")

        // The summary itself stays out of the conversation until asked for.
        XCTAssertFalse(app.staticTexts["I considered the question, and then I answered it."].exists)
        thinking.tap()
        XCTAssert(
            app.staticTexts["I considered the question, and then I answered it."].waitForExistence(timeout: 5),
            "Opening the disclosure should show what the model was thinking."
        )
    }

    func testAToolCallAndItsResponseAreShown() throws {
        let app = XCUIApplication()
        try send("call the function", in: app)

        XCTAssert(
            app.staticTexts["call_test_func({ test: true })"].waitForExistence(timeout: 20),
            "A tool call should be visible in the conversation."
        )
        XCTAssert(
            app.staticTexts["{ some: response }"].waitForExistence(timeout: 20),
            "Its response should follow it."
        )
        XCTAssert(app.staticTexts["Assistant Message Response!"].waitForExistence(timeout: 20))
    }

    func testAGeneratedImageIsRendered() throws {
        let app = XCUIApplication()
        let imagesBefore = app.images.count
        try send("draw something", in: app)

        XCTAssert(app.staticTexts["Here's what I came up with."].waitForExistence(timeout: 20))
        XCTAssert(
            app.images.count > imagesBefore,
            "The generated image should reach the conversation alongside its caption."
        )
    }

    func testAMarkdownTableIsLaidOutAsATable() throws {
        let app = XCUIApplication()
        try send("what is the weather", in: app)

        // What matters is that the Markdown was interpreted rather than dumped: the rows are readable and the
        // separator row, which carries no content, never reaches the screen.
        XCTAssert(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Munich")).firstMatch
                .waitForExistence(timeout: 20),
            "The table's rows should render."
        )
        XCTAssert(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Svalbard")).firstMatch.exists,
            "Every row should render, not just the first."
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "|---")).firstMatch.exists,
            "The Markdown separator row should not be shown verbatim."
        )
    }

    func testAFencedCodeBlockIsRendered() throws {
        let app = XCUIApplication()
        try send("show me fib", in: app)

        XCTAssert(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "fn fib")).firstMatch
                .waitForExistence(timeout: 20),
            "The code block's contents should render."
        )
    }

    func testTheTypingIndicatorAppearsWhileAnsweringAndLeavesAfterwards() throws {
        let app = XCUIApplication()
        try send("hello there", in: app)

        XCTAssert(app.otherElements["Typing Indicator"].waitForExistence(timeout: 5), "The chat should show it is working.")
        XCTAssert(app.otherElements["Typing Indicator"].waitForNonExistence(timeout: 20), "It should go once the answer lands.")
        XCTAssert(app.staticTexts["Assistant Message Response!"].exists)
    }

    private func send(_ message: String, in app: XCUIApplication) throws {
        let composer = app.textFields["Message Input Textfield"]
        XCTAssert(composer.wait(for: \.isHittable, toEqual: true, timeout: 5))
        try composer.enter(value: message, options: [.disableKeyboardDismiss])
        let send = app.buttons["Send Message"]
        XCTAssert(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
        send.tap()
    }
}
