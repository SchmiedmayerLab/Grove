//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
@testable import XCTestExtensions


@MainActor
final class TextEntryTests: XCTestCase, Sendable {
    private let app = XCUIApplication()
    
    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        MainActor.assumeIsolated {
            continueAfterFailure = false
            simulateFlakySimulatorTextEntry = false
            app.launch()
            XCTAssert(app.wait(for: .runningForeground, timeout: 4))
        }
    }
    
    
    @MainActor
    func testTextEntry() throws {
        try _testTextEntry(simulateFlakyKeyboard: false)
    }
    
    
    @MainActor
    func testFlakyTextEntry() throws {
        try _testTextEntry(simulateFlakyKeyboard: true)
    }
    
    @MainActor
    private func _testTextEntry(simulateFlakyKeyboard: Bool) throws {
        simulateFlakySimulatorTextEntry = simulateFlakyKeyboard
        app.buttons["Text Entry"].tap()
        
        XCTAssert(app.staticTexts["No text set ..."].waitForExistence(timeout: 5))
        let textField = app.textFields["TextField"]
        XCTAssert(textField.exists)
        try textField.enter(value: "Example Text")
        XCTAssert(app.staticTexts["Example Text"].waitForExistence(timeout: 5))
        try textField.delete(count: 5)
        XCTAssert(app.staticTexts[simulateFlakyKeyboard ? "Example " : "Example"].waitForExistence(timeout: 5))
        
        try textField.delete(count: 42)
        XCTAssert(app.staticTexts["No text set ..."].waitForExistence(timeout: 5))
        XCTAssertEqual(textField.textFieldValue, "")
        
        #if os(iOS)
        app.dismissKeyboard()
        app.swipeUp()
        #endif
        
        XCTAssert(app.staticTexts["No secure text set ..."].waitForExistence(timeout: 5))
        let secureTextField = app.secureTextFields["SecureField"]
        XCTAssert(secureTextField.exists)
        try secureTextField.enter(value: "Secure Text")
        XCTAssert(app.staticTexts["Secure Text"].waitForExistence(timeout: 5))
        
        try secureTextField.delete(count: 42)
        XCTAssert(app.staticTexts["No secure text set ..."].waitForExistence(timeout: 5))
        
        XCTAssertFalse(app.staticTexts["Button was pressed!"].exists)
    }
    
    @MainActor
    func testLongTextEntries() throws {
        app.buttons["Text Entry"].tap()
        
        XCTAssert(app.staticTexts["No text set ..."].waitForExistence(timeout: 5))
        let textField = app.textFields["TextField"]
        
        let message = "This is a very long text and some more"
        try textField.enter(value: message, options: .skipTextInputValidation)
        XCTAssert(app.staticTexts[message].waitForExistence(timeout: 5))
        #if os(visionOS)
        try textField.enter(value: " ...", options: [.skipTextInputValidation])
        #else
        try textField.enter(value: " ...", options: [.skipTextInputValidation, .tapFromRight])
        #endif
        XCTAssert(app.staticTexts["\(message) ..."].waitForExistence(timeout: 5))
        
        // Test text field deletion with longer text input
        try textField.delete(count: message.count + 4)
    }
    
    
    @MainActor
    func testClearTextField() throws {
        app.buttons["Text Entry"].tap()
        let text = repeatElement("Hello There", count: 5).joined()
        let textField = app.textFields["TextField"]
        XCTAssertEqual(textField.textFieldValue, "")
        try textField.enter(value: text)
        XCTAssertEqual(textField.textFieldValue, text)
        // look into why this sometimes doesnt properly jump all the way to the right.
        try textField.clear()
        XCTAssertEqual(textField.textFieldValue, "")
    }
    
    
    @MainActor
    func testDeleteLongTextField() throws {
        app.buttons["Text Entry"].tap()
        let text = repeatElement("Hello There", count: 5).joined()
        let textField = app.textFields["TextField"]
        XCTAssertEqual(textField.textFieldValue, "")
        try textField.enter(value: text)
        XCTAssertEqual(textField.textFieldValue, text)
        try textField.delete(count: text.count)
        XCTAssertEqual(textField.textFieldValue, "")
    }
    
    
    @MainActor
    func testKeyboardBehavior() throws {
        // make sure you disconnect the hardware keyboard when running this test! Also language must be english.
        app.buttons["DismissKeyboard"].tap()
        let checkLabel = { [app] (label: String) in
            XCTAssert(app.textFields[label].exists)
            try app.textFields[label].selectTextField()
            #if os(visionOS)
            XCTAssert(app.visionOSKeyboard.wait(for: .runningForeground, timeout: 2.0))
            #elseif !os(macOS)
            XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 2.0))
            #endif
            
            app.dismissKeyboard()
            #if !os(visionOS) && !os(macOS)
            XCTAssert(app.keyboards.firstMatch.waitForNonExistence(timeout: 2.0))
            #endif
        }
        
        // this way we know exactly which button failed by line numbers.
        try checkLabel("Continue")
        try checkLabel("Done")
        try checkLabel("Go")
        try checkLabel("Join")
        try checkLabel("Next")
        try checkLabel("Return")
        try checkLabel("Route")
        try checkLabel("Search")
        try checkLabel("Send")
    }
    
    @MainActor
    func testNumberPadDismissal() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            // iPhoneOS number pads don't have a universal dismissal mechanism, bc there is no submit/return button.
            // depending on the specific configuration of the view being presented, there might be some kind of
            // ScrollView-based (interactive) dismissal situation going on, but nothing that can be relied upon reliably.
            throw XCTSkip("Not applicable")
        }
        app.buttons["DismissKeyboard"].tap()
        let textField = app.textFields["Number Entry"]
        XCTAssert(textField.waitForExistence(timeout: 2))
        XCTAssertFalse(app.keyboards.element.exists)
        try textField.enter(value: "12", options: [.disableKeyboardDismiss])
        XCTAssert(app.keyboards.element.exists)
        app.dismissKeyboard()
        XCTAssert(app.keyboards.element.waitForNonExistence(timeout: 2))
    }
}
