//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Drives the test app against a real provider.
///
/// The unit tests exercise sessions directly; this covers what they cannot — that a message typed into the composer
/// reaches the model and that the answer comes back into the chat. The token is handed to the *app* through its
/// environment (`TEST_RUNNER_OPENAI_API_TOKEN`) rather than typed through the interface, so no secret passes through
/// the UI or its screenshots. Without a token the app falls back to the keychain and this test skips.
final class LLMLiveChatUITests: TestAppTestCase {
    func testAMessageTypedIntoTheChatIsAnsweredByTheModel() throws {
        let openAIButton = app.buttons["LLMOpenAI"]
        launch(enableMockMode: false, showOnboarding: false, clearAPIKeysFromKeychain: false, waitingFor: openAIButton)

        guard app.otherElements["Live Provider Configured"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Pass TEST_RUNNER_OPENAI_API_TOKEN to run the live chat UI test.")
        }
        openAIButton.tap()

        let composer = app.textFields["Message Input Textfield"]
        XCTAssert(composer.wait(for: \.isHittable, toEqual: true, timeout: 10), "The chat should come up.")
        try composer.enter(value: "Reply with exactly the word: ok", options: [.disableKeyboardDismiss])

        let send = app.buttons["Send Message"]
        XCTAssert(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
        send.tap()

        let answered = NSPredicate(format: "label CONTAINS[c] %@", "ok")
        let answer = app.staticTexts.containing(answered).firstMatch
        XCTAssert(answer.waitForExistence(timeout: 90), "The model's answer never reached the chat.")
    }
}
