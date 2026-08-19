//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class TestAppLLMOpenAIUITests: TestAppTestCase {
    func testGroveLLMOpenAIOnboarding() throws {    // swiftlint:disable:this function_body_length
        let openAIButton = app.buttons["LLMOpenAI"]
        launch(enableMockMode: true, showOnboarding: false, clearAPIKeysFromKeychain: true, waitingFor: openAIButton)
        openAIButton.tap()

        let onboardingButton = app.buttons["Onboarding"].firstMatch
        XCTAssert(onboardingButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        onboardingButton.tap()

        let apiKeyField = app.textFields["API Key…"]
        XCTAssert(apiKeyField.wait(for: \.isHittable, toEqual: true, timeout: 5))
        try apiKeyField.enter(value: "New Token")

        // The action button stays disabled until the entered token has propagated to the view's state.
        let continueButton = app.buttons["Continue"]
        XCTAssert(continueButton.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        continueButton.tap()

        #if os(macOS)
        let modelPicker = app.popUpButtons["modelPicker"]
        XCTAssert(modelPicker.wait(for: \.isHittable, toEqual: true, timeout: 5))
        modelPicker.tap()
        let modelMenuItem = app.menuItems["gpt-5-chat-latest"]
        XCTAssert(modelMenuItem.wait(for: \.isHittable, toEqual: true, timeout: 5))
        modelMenuItem.tap()
        XCTAssert(app.popUpButtons["gpt-5-chat-latest"].waitForExistence(timeout: 5))
        #elseif os(visionOS)
        let modelPickerWheel = app.pickers["modelPicker"].pickerWheels.element(boundBy: 0)
        XCTAssert(modelPickerWheel.wait(for: \.isHittable, toEqual: true, timeout: 5))
        modelPickerWheel.swipeUp()
        XCTAssert(app.pickerWheels["gpt-3.5-turbo"].waitForExistence(timeout: 5))     // swipe down to the gpt-3.5-turbo model
        #else
        let modelPickerWheel = app.pickers["modelPicker"].pickerWheels.element(boundBy: 0)
        XCTAssert(modelPickerWheel.wait(for: \.isHittable, toEqual: true, timeout: 5))
        modelPickerWheel.adjust(toPickerWheelValue: "gpt-5-chat-latest")
        XCTAssert(app.pickerWheels["gpt-5-chat-latest"].waitForExistence(timeout: 5))
        #endif

        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        continueButton.tap()

        #if !os(macOS)
        let alert = app.alerts["Model Selected"]

        XCTAssertTrue(alert.waitForExistence(timeout: 5), "The `Model Selected` alert did not appear.")
        #if os(visionOS)
        XCTAssertTrue(alert.staticTexts["gpt-3.5-turbo"].exists, "The correct model was not registered.")
        #else
        XCTAssertTrue(alert.staticTexts["gpt-5-chat-latest"].exists, "The correct model was not registered.")
        #endif

        let okButton = alert.buttons["OK"]
        XCTAssertTrue(okButton.wait(for: \.isHittable, toEqual: true, timeout: 5), "The OK button on the alert was not found.")
        okButton.tap()
        #else
        XCTAssertTrue(app.staticTexts["Model Selected"].waitForExistence(timeout: 5), "The `Model Selected` alert did not appear.")
        XCTAssertTrue(app.staticTexts["gpt-5-chat-latest"].exists, "The correct model was not registered.")
        let okButton = app.buttons["OK"].firstMatch
        XCTAssert(okButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        okButton.tap()
        #endif

        XCTAssert(app.textFields["New Token"].waitForExistence(timeout: 5))

        app.terminate()
        launch(enableMockMode: true, showOnboarding: false, clearAPIKeysFromKeychain: false, waitingFor: openAIButton)
        openAIButton.tap()

        XCTAssert(onboardingButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        onboardingButton.tap()

        // The stored token is read back in the view's task, which also re-enables the action button.
        XCTAssert(app.textFields["New Token"].waitForExistence(timeout: 5))
        XCTAssert(continueButton.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        continueButton.tap()

        #if !os(macOS)
        XCTAssert(app.pickerWheels["gpt-4o"].waitForExistence(timeout: 5))
        #else
        XCTAssert(app.popUpButtons["gpt-4o"].waitForExistence(timeout: 5))
        #endif
        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        continueButton.tap()

        #if !os(macOS)
        let alert2 = app.alerts["Model Selected"]

        XCTAssertTrue(alert2.waitForExistence(timeout: 5), "The `Model Selected` alert did not appear.")
        XCTAssertTrue(alert2.staticTexts["gpt-4o"].exists, "The correct model was not registered.")

        let okButton2 = alert2.buttons["OK"]
        XCTAssertTrue(okButton2.wait(for: \.isHittable, toEqual: true, timeout: 5), "The OK button on the alert was not found.")
        okButton2.tap()
        #else
        XCTAssertTrue(app.staticTexts["Model Selected"].waitForExistence(timeout: 5), "The `Model Selected` alert did not appear.")
        XCTAssertTrue(app.staticTexts["gpt-5"].exists, "The correct model was not registered.")
        let okButton2 = app.buttons["OK"].firstMatch
        XCTAssert(okButton2.wait(for: \.isHittable, toEqual: true, timeout: 5))
        okButton2.tap()
        #endif

        app.terminate()
        launch(enableMockMode: true, showOnboarding: false, clearAPIKeysFromKeychain: false, waitingFor: openAIButton)
        openAIButton.tap()

        XCTAssert(onboardingButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        onboardingButton.tap()

        XCTAssert(app.textFields["API Key…"].waitForExistence(timeout: 5))

        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        continueButton.tap()

        #if !os(macOS)
        XCTAssert(app.pickerWheels["gpt-4o"].waitForExistence(timeout: 5))
        #else
        XCTAssert(app.popUpButtons["gpt-4o"].waitForExistence(timeout: 5))
        #endif
    }
    
    
    func testGroveLLMOpenAIChat() throws {
        let openAIButton = app.buttons["LLMOpenAI"]
        launch(enableMockMode: true, showOnboarding: false, clearAPIKeysFromKeychain: true, waitingFor: openAIButton)
        openAIButton.tap()

        XCTAssertFalse(app.staticTexts["You're a helpful assistant that answers questions from users."].waitForExistence(timeout: 2))

        let inputTextfield = app.textFields["Message Input Textfield"]
        XCTAssert(inputTextfield.wait(for: \.isHittable, toEqual: true, timeout: 10))

        try inputTextfield.enter(value: "New Message!", options: [.disableKeyboardDismiss])

        let sendButton = app.buttons["Send Message"]
        XCTAssert(sendButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        sendButton.tap()

        // The mock session idles for a second and then streams its four tokens half a second apart.
        XCTAssert(app.staticTexts["Mock Message from GroveLLM!"].waitForExistence(timeout: 15))
    }
}
