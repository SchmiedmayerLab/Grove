//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: launch-arguments --documentation
// documentation-screenshots: copy Conversation Sources/Grove/Grove.docc/Resources/Chat.png
// documentation-screenshots: copy Conversation Sources/GroveLLM/GroveLLM.docc/Resources/ImageGeneration.png
// documentation-screenshots: copy ToolCall Sources/GroveLLMOpenAI/GroveLLMOpenAI.docc/Resources/ToolCall.png
// documentation-screenshots: copy ToolCall Sources/Grove/Grove.docc/Resources/ToolCall.png

/// Walks the chat to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
final class DocumentationScreenshots: XCTestCase {
    override func setUpWithError() throws {
        // The walk needs the app the script launched and the states it prepared; a plain test run skips it.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GROVE_DOCUMENTATION_SCREENSHOTS"] == "1",
            "Run through Scripts/documentation-screenshots.sh"
        )
        continueAfterFailure = false
    }

    func testCaptureDocumentationScreenshots() throws {
        let app = XCUIApplication()
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssert(app.textFields["Message Input Textfield"].waitForExistence(timeout: 10))
        // The assistant answers the last message with a picture; the placeholder gives way to it after a few seconds.
        sleep(9)
        capture("Conversation")

        let images = app.images.matching(identifier: "Attached Image")
        XCTAssert(images.count > 1)
        images.element(boundBy: 1).tap()
        let shareImage = app.buttons["Share Image"]
        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"),
            object: shareImage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 10), .completed, "the image viewer never settled")
        sleep(2)
        capture("ImageViewer")
        app.buttons.matching(NSPredicate(format: "label IN {'Done', 'Close'}")).firstMatch.tap()
        sleep(1)

        // The follow-up sits on the text selection's own menu, which a double tap on a word brings up. The caption
        // opens with the word to quote, so the tap lands on it at the start of the first line.
        let caption = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Oats'")).firstMatch
        XCTAssert(caption.waitForExistence(timeout: 3))
        caption.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.15)).doubleTap()
        let followUp = app.menuItems["Follow Up"].firstMatch
        XCTAssert(followUp.waitForExistence(timeout: 3))
        followUp.tap()
        XCTAssert(app.staticTexts["Oats"].waitForExistence(timeout: 3), "The quote should carry the word that was tapped.")
        // The quote does not always take the field's focus with it, and the composer then floats over the
        // conversation with no keyboard under it. A tap on a field that already has the focus opens its
        // AutoFill menu instead, so the focus is what decides.
        let field = app.textFields["Message Input Textfield"]
        if !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field) {
            field.tap()
        }
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the composer never took focus")
        sleep(1)
        capture("FollowUp")

        // The next question is typed and shown in the composer before it goes out.
        app.textFields["Message Input Textfield"].tap()
        app.typeText("Why oats?")
        sleep(1)
        capture("Composer")

        // A question about the oats is answered with its sources.
        app.buttons["Send Message"].tap()
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Oats carry'")).firstMatch.waitForExistence(timeout: 15))
        dismissChatKeyboard(app)
        sleep(2)
        capture("Citations")

        // A question about earlier results is answered through a tool.
        send("What was my LDL last time?")
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your previous LDL'")).firstMatch.waitForExistence(timeout: 15))
        dismissChatKeyboard(app)
        sleep(2)
        capture("ToolCall")

        // Messages written while the next answer is drawn wait in a stack, and fan out over the conversation.
        send("Could you also draw one for the HbA1c?")
        XCTAssert(app.buttons["Stop Generating"].waitForExistence(timeout: 3))
        // With the conversation at its end, the stack of queued messages covers the bottom of the chat rather
        // than the middle of an answer. Dragging it once the messages are queued would take the stack down again.
        scrollToEnd(app)
        for text in ["And one for exercise?", "Thanks!"] {
            app.textFields["Message Input Textfield"].tap()
            app.typeText(text)
            app.buttons["Queue Message"].tap()
        }
        sleep(1)
        capture("Queue")
        app.buttons["Show Queued Messages"].tap()
        XCTAssert(app.descendants(matching: .any)["Queued Messages"].waitForExistence(timeout: 3))
        sleep(1)
        capture("QueuedMessages")
    }

    /// Drags the conversation to its end.
    private func scrollToEnd(_ app: XCUIApplication) {
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        }
    }

    /// The chat drops its keyboard when the conversation is dragged down onto it; the return key would only add a line.
    private func dismissChatKeyboard(_ app: XCUIApplication) {
        // One drag does not always take the keyboard down, and a picture with it up shows half the answer.
        for _ in 0..<3 where app.keyboards.firstMatch.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            start.press(forDuration: 0.1, thenDragTo: end)
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        XCTAssert(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "the keyboard stayed up")
        // The drag also scrolled the conversation up; two swipes bring the newest messages back into view.
        app.swipeUp()
        app.swipeUp()
        sleep(1)
    }

    private func send(_ text: String) {
        let app = XCUIApplication()
        app.textFields["Message Input Textfield"].tap()
        app.typeText(text)
        app.buttons["Send Message"].tap()
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(12) // long enough for the script's two shots and their checks
    }
}
