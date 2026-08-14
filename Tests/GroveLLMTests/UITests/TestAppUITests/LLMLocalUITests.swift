//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class TestAppLLMLocalUITests: TestAppTestCase {
    func testGroveLLMLocal() throws {
        let localButton = app.buttons["LLMLocal"]
        launch(enableMockMode: true, showOnboarding: true, clearAPIKeysFromKeychain: true, waitingFor: localButton)
        localButton.tap()

        // Onboarding
        XCTAssert(app.staticTexts["Local LLM Execution"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["LLMs on an iPhone"].exists)
        XCTAssert(app.staticTexts["Swift Package Manager"].exists)
        XCTAssert(app.staticTexts["The Stanford Grove ecosystem"].exists)

        let nextButton = app.buttons["Next"]
        XCTAssert(nextButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        nextButton.tap()

        // Chat, reachable once the onboarding sheet has dismissed
        let inputTextfield = app.textFields["Message Input Textfield"]
        XCTAssert(inputTextfield.wait(for: \.isHittable, toEqual: true, timeout: 10))

        try inputTextfield.enter(value: "New Message!", options: [.disableKeyboardDismiss])

        let sendButton = app.buttons["Send Message"]
        XCTAssert(sendButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        sendButton.tap()

        XCTAssert(app.staticTexts["New Message!"].waitForExistence(timeout: 5))

        // The mock session idles for a second and then streams its four tokens half a second apart.
        XCTAssert(app.staticTexts["Mock Message from GroveLLM!"].waitForExistence(timeout: 15))
    }
}
