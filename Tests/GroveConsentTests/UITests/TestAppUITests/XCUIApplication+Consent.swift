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
        func assertContinueButtonEnabledState(_ isEnabled: Bool, line: UInt = #line) {
            assertReady(continueButton, isEnabled, line: line)
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
        // The eraser only appears once there is ink to clear.
        XCTAssertFalse(buttons["Clear"].exists)
        
        assertContinueButtonEnabledState(false)
        staticTexts["Name: Leland Stanford"].swipeRight()
        assertContinueButtonEnabledState(true)
        
        XCTAssert(buttons["Clear"].waitForExistence(timeout: 2.0))
        XCTAssert(buttons["Clear"].isEnabled)
        buttons["Clear"].tap()
        assertContinueButtonEnabledState(false)
        XCTAssert(buttons["Clear"].waitForNonExistence(timeout: 2.0))
        
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
            assertReady(continueButton, isComplete, line: line)
            XCTAssert(shareButton.wait(for: \.isEnabled, toEqual: isComplete, timeout: 5), line: line)
        }

        assertExpectedCompletion(false)

        func flipToggle(beforeValue: Bool, afterValue: Bool, line: UInt = #line) throws {
            let element = switches["ConsentForm:data-sharing"].firstMatch
            XCTAssert(element.waitForExistence(timeout: 5), line: line)
            XCTAssert(element.wait(for: \.toggleState, toEqual: beforeValue, timeout: 5), line: line)
            try element.toggleSwitch()
            XCTAssert(element.wait(for: \.toggleState, toEqual: afterValue, timeout: 5), line: line)
        }

        assertExpectedCompletion(false)
        try flipToggle(beforeValue: false, afterValue: true)
        assertExpectedCompletion(false)

        #if !os(visionOS)
        swipeUp()
        #endif

        func select(in elementId: String, option: String?, expectedCurrentSelection: String?, line: UInt = #line) throws {
            let noSelectionTitle = "(No selection)"
            let button = buttons["ConsentForm:\(elementId)"]
            XCTAssert(button.waitForExistence(timeout: 5), line: line)
            // A tap while the keyboard is up only puts it away; the menu opens on the next one.
            if keyboards.firstMatch.exists {
                staticTexts[consentTitle].firstMatch.tap()
            }
            // Entering the names leaves the first picker scrolled under the bars, where a tap never opens its menu.
            let barBottom = navigationBars.firstMatch.frame.maxY
            if button.frame.minY < barBottom {
                let start = coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: barBottom + 24))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: barBottom - button.frame.minY + 24)))
            }
            XCTAssert(button.staticTexts[expectedCurrentSelection ?? noSelectionTitle].waitForExistence(timeout: 3), line: line)
            button.tap()
            XCTAssert(buttons[option ?? noSelectionTitle].waitForExistence(timeout: 3), line: line)
            buttons[option ?? noSelectionTitle].tap()
            XCTAssert(button.staticTexts[expectedCurrentSelection ?? noSelectionTitle].waitForNonExistence(timeout: 3), line: line)
            XCTAssert(button.staticTexts[option ?? noSelectionTitle].waitForExistence(timeout: 3), line: line)
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
            XCTAssert(signatureCanvas.waitForExistence(timeout: 5))
            signatureCanvas.swipeRight()
        }

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

        assertExpectedCompletion(true)
        try flipToggle(beforeValue: true, afterValue: false)
        assertExpectedCompletion(false)
        try flipToggle(beforeValue: false, afterValue: true)
        assertExpectedCompletion(true)
        
        shareButton.tap()
        assertShareSheetTextElementExists(consentTitle)
        navigationBars["UIActivityContentView"].buttons["header.closeButton"].tap()
        // The share sheet is a remote view; the app reports idle while it is still sliding away, and a tap
        // that lands during the dismissal is swallowed.
        XCTAssert(navigationBars["UIActivityContentView"].waitForNonExistence(timeout: 5))
        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        continueButton.tap()
    }
}


extension XCUIApplication {
    /// The onboarding's button stays tappable and reports readiness as its value; a plain button reports it as enabled.
    fileprivate func assertReady(_ button: XCUIElement, _ isReady: Bool, line: UInt = #line) {
        XCTAssert(button.waitForExistence(timeout: 5), line: line)
        if let value = button.value as? String, ["Ready", "Incomplete"].contains(value) {
            let expected = isReady ? "Ready" : "Incomplete"
            let deadline = Date().addingTimeInterval(5)
            while (button.value as? String) != expected && Date() < deadline {
                usleep(200_000)
            }
            XCTAssertEqual(button.value as? String, expected, line: line)
        } else {
            XCTAssert(button.wait(for: \.isEnabled, toEqual: isReady, timeout: 5), line: line)
        }
    }
}
