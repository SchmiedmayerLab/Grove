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
        XCTAssert(app.buttons["Share Image"].waitForExistence(timeout: 5))
        sleep(1)
        capture("ImageViewer")
        app.buttons.matching(NSPredicate(format: "label IN {'Done', 'Close'}")).firstMatch.tap()
        sleep(1)

        // The follow-up sits on the text selection's own menu, which a double tap on a word brings up.
        let assistantMessage = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your resting heart rate'")).firstMatch
        XCTAssert(assistantMessage.waitForExistence(timeout: 3))
        assistantMessage.doubleTap()
        let followUp = app.menuItems["Follow Up"].firstMatch
        XCTAssert(followUp.waitForExistence(timeout: 3))
        followUp.tap()
        sleep(1)
        capture("FollowUp")

        // The next question is typed and shown in the composer before it goes out.
        app.textFields["Message Input Textfield"].tap()
        app.typeText("Is 64 still normal?")
        sleep(1)
        capture("Composer")

        // A question about the numbers is answered with its sources.
        app.buttons["Send Message"].tap()
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'A resting heart rate in the 60s'")).firstMatch.waitForExistence(timeout: 15))
        dismissChatKeyboard(app)
        sleep(2)
        capture("Citations")

        // A question about the data is answered through a tool.
        send("What was my average over the whole month?")
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Over the last 30 days'")).firstMatch.waitForExistence(timeout: 15))
        dismissChatKeyboard(app)
        sleep(2)
        capture("ToolCall")
    }

    /// The chat drops its keyboard when the conversation is dragged down onto it; the return key would only add a line.
    private func dismissChatKeyboard(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.1, thenDragTo: end)
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
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
        sleep(5)
    }
}
