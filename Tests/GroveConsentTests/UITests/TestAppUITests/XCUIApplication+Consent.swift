//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions

extension XCUIApplication {
    func fillOutSimpleConsent(
        consentTitle: String,
        consentText: String,
        continueButton: XCUIElement
    ) throws {
        func assertContinueButtonEnabledState(_ isEnabled: Bool) {
            XCTAssert(continueButton.wait(for: \.isEnabled, toEqual: isEnabled, timeout: 2))
        }
        
        XCTAssert(staticTexts[consentTitle].waitForExistence(timeout: 2))
        XCTAssert(staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", consentText)).element.waitForExistence(timeout: 1))
        assertContinueButtonEnabledState(false)

        #if targetEnvironment(simulator) && (arch(i386) || arch(x86_64))
        throw XCTSkip("PKCanvas view-related tests are currently skipped on Intel-based iOS simulators due to a metal bug on the simulator.")
        #endif

        XCTAssert(staticTexts["First Name"].waitForExistence(timeout: 2))
        try textFields["Enter your first name…"].enter(value: "Leland")
        assertContinueButtonEnabledState(false)
        XCTAssert(staticTexts["Last Name"].waitForExistence(timeout: 2))
        try textFields["Enter your last name…"].enter(value: "Stanford")
        assertContinueButtonEnabledState(false)
        
        XCTAssert(staticTexts["Name: Leland Stanford"].waitForExistence(timeout: 2))

        #if !os(macOS)
        XCTAssert(buttons["Clear"].waitForExistence(timeout: 2.0))
        XCTAssertFalse(buttons["Clear"].isEnabled)
        
        assertContinueButtonEnabledState(false)
        staticTexts["Name: Leland Stanford"].swipeRight()
        assertContinueButtonEnabledState(true)
        
        XCTAssert(buttons["Clear"].waitForExistence(timeout: 2.0))
        XCTAssert(buttons["Clear"].isEnabled)
        buttons["Clear"].tap()
        assertContinueButtonEnabledState(false)
        
        XCTAssert(buttons["Clear"].waitForExistence(timeout: 2.0))
        XCTAssertFalse(buttons["Clear"].isEnabled)
        
        XCTAssert(scrollViews["Signature Field"].waitForExistence(timeout: 2))
        scrollViews["Signature Field"].swipeRight()
        assertContinueButtonEnabledState(true)
        
        XCTAssert(buttons["Clear"].waitForExistence(timeout: 2.0))
        XCTAssert(buttons["Clear"].isEnabled)
        assertContinueButtonEnabledState(true)
        #else
        XCTAssert(textFields["Signature Field"].waitForExistence(timeout: 2))
        try textFields["Signature Field"].enter(value: "Leland Stanford")
        #endif
        
        assertContinueButtonEnabledState(true)
        continueButton.tap()
    }
    
    
    func fillOutInteractiveConsent( // swiftlint:disable:this function_body_length
        consentTitle: String,
        consentText: String,
        continueButton: XCUIElement
    ) throws {
        XCTAssert(staticTexts[consentTitle].waitForExistence(timeout: 1))
        XCTAssert(staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", consentText)).element.waitForExistence(timeout: 1))
        
        let shareButton = buttons["Share Consent Form"]
        XCTAssert(shareButton.waitForExistence(timeout: 1))
        
        func assertExpectedCompletion(_ isComplete: Bool, line: UInt = #line) {
            for button in [continueButton, shareButton] {
                XCTAssertEqual(button.isEnabled, isComplete, line: line)
            }
        }
        
        assertExpectedCompletion(false)
        
        func flipToggle(beforeValue: Bool, afterValue: Bool, line: UInt = #line) throws {
            let element = switches["ConsentForm:data-sharing"].firstMatch
            XCTAssert(element.exists, line: line)
            XCTAssertEqual(try XCTUnwrap(XCTUnwrap(element.value) as? String), beforeValue ? "1" : "0", line: line)
            try element.toggleSwitch()
            sleep(for: .seconds(0.25))
            XCTAssertEqual(try XCTUnwrap(XCTUnwrap(element.value) as? String), afterValue ? "1" : "0", line: line)
        }
        
        assertExpectedCompletion(false)
        try flipToggle(beforeValue: false, afterValue: true)
        assertExpectedCompletion(false)
        
        #if !os(visionOS)
        swipeUp()
        #endif
        sleep(for: .seconds(1))
        
        func select(in elementId: String, option: String?, expectedCurrentSelection: String?, line: UInt = #line) throws {
            let noSelectionTitle = "(No selection)"
            let button = buttons["ConsentForm:\(elementId)"]
            XCTAssert(button.exists)
            XCTAssert(button.staticTexts[expectedCurrentSelection ?? noSelectionTitle].waitForExistence(timeout: 1), line: line)
            button.tap()
            buttons[option ?? noSelectionTitle].tap()
            sleep(for: .seconds(0.25))
            XCTAssert(button.staticTexts[expectedCurrentSelection ?? noSelectionTitle].waitForNonExistence(timeout: 1), line: line)
            XCTAssert(button.staticTexts[option ?? noSelectionTitle].waitForExistence(timeout: 1), line: line)
        }
        
        assertExpectedCompletion(false)
        try select(in: "select1", option: "Mountains", expectedCurrentSelection: nil)
        assertExpectedCompletion(false)
        
        try select(in: "select2", option: "No", expectedCurrentSelection: nil)
        
        do {
            for (nameComponent, name) in zip(["first", "last"], ["Leland", "Stanford"]) {
                let textField = textFields["Enter your \(nameComponent) name…"]
                XCTAssert(textField.waitForExistence(timeout: 2))
                try textField.enter(value: name)
            }
            assertExpectedCompletion(false)
            let signatureCanvas = scrollViews["ConsentForm:sig"]
            signatureCanvas.swipeRight()
        }
        sleep(for: .seconds(1))
        
        assertExpectedCompletion(true)
        try select(in: "select1", option: nil, expectedCurrentSelection: "Mountains")
        assertExpectedCompletion(false)
        try select(in: "select1", option: "Beach", expectedCurrentSelection: nil)
        assertExpectedCompletion(true)
        try select(in: "select1", option: "Mountains", expectedCurrentSelection: "Beach")
        assertExpectedCompletion(true)
        
        #if !os(visionOS)
        swipeDown()
        #endif
        sleep(for: .seconds(1))
        
        assertExpectedCompletion(true)
        try flipToggle(beforeValue: true, afterValue: false)
        assertExpectedCompletion(false)
        try flipToggle(beforeValue: false, afterValue: true)
        assertExpectedCompletion(true)
        
        shareButton.tap()
        assertShareSheetTextElementExists(consentTitle)
        navigationBars["UIActivityContentView"].buttons["header.closeButton"].tap()
        
        continueButton.tap()
    }
}
