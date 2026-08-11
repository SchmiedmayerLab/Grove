//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import XCTest
import XCTestExtensions


final class ConsentTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }
    
    
    @MainActor
    func testStandaloneSimpleConsent() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 2))
        let standaloneSection = app.collectionViews.otherElements["Section:Standalone"]
        
        for consentName in ["First Consent", "Second Consent"] {
            XCTAssertFalse(standaloneSection.buttons["\(consentName) (Rendered)"].isEnabled)
            standaloneSection.buttons[consentName].tap()
            XCTAssert(app.navigationBars[consentName].waitForExistence(timeout: 1))
            try app.fillOutSimpleConsent(
                consentTitle: consentName,
                consentText: "This is the \(try XCTUnwrap(consentName.components(separatedBy: " ").first).lowercased()) markdown example",
                continueButton: app.navigationBars.buttons["Done"]
            )
            XCTAssert(app.navigationBars[consentName].waitForNonExistence(timeout: 2))
            XCTAssert(standaloneSection.buttons["\(consentName) (Rendered)"].isEnabled)
            standaloneSection.buttons["\(consentName) (Rendered)"].tap()
            XCTAssert(app.staticTexts["\(consentName) PDF rendering exists"].waitForExistence(timeout: 1))
            app.navigationBars.buttons["Next"].tap()
        }
    }
    
    
    @MainActor
    func testStandaloneInteractiveConsent() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))
        
        let standaloneSection = app.collectionViews.otherElements["Section:Standalone"]
        let consentTitle = "Knee Replacement Study Consent Form"
        
        standaloneSection.buttons[consentTitle].tap()
        try app.fillOutInteractiveConsent(
            consentTitle: "Knee Replacement Study Consent Form",
            consentText: "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
            continueButton: app.navigationBars.buttons["Done"]
        )
        
        XCTAssert(standaloneSection.buttons["\(consentTitle) (Rendered)"].isEnabled)
        standaloneSection.buttons["\(consentTitle) (Rendered)"].tap()
        
        XCTAssert(app.staticTexts["\(consentTitle) PDF rendering exists"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["data-sharing, true"].exists)
        XCTAssert(app.staticTexts["select1, m"].exists)
        XCTAssert(app.staticTexts["select2, n"].exists)
        XCTAssert(app.staticTexts["Name, Leland Stanford"].waitForExistence(timeout: 1))
        app.navigationBars.buttons["Next"].tap()
    }
    
    
    @MainActor
    func testOnboardingConsent() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))
        
        app.buttons["Start Onboarding Flow"].tap()
        for consentName in ["First Consent", "Second Consent"] {
            try app.fillOutSimpleConsent(
                consentTitle: consentName,
                consentText: "This is the \(try XCTUnwrap(consentName.components(separatedBy: " ").first).lowercased()) markdown example",
                continueButton: app.buttons["I Consent"]
            )
        }
        try app.fillOutInteractiveConsent(
            consentTitle: "Knee Replacement Study Consent Form",
            consentText: "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
            continueButton: app.buttons["I Consent"]
        )
        
        XCTAssert(app.staticTexts["First Consent PDF rendering exists"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Name, Leland Stanford"].exists)
        app.navigationBars.buttons["Next"].tap()
        
        XCTAssert(app.staticTexts["Second Consent PDF rendering exists"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Name, Leland Stanford"].exists)
        app.navigationBars.buttons["Next"].tap()
        
        XCTAssert(app.staticTexts["Knee Replacement Study Consent Form PDF rendering exists"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["data-sharing, true"].exists)
        XCTAssert(app.staticTexts["select1, m"].exists)
        XCTAssert(app.staticTexts["select2, n"].exists)
        XCTAssert(app.staticTexts["Name, Leland Stanford"].waitForExistence(timeout: 1))
        
        app.navigationBars.buttons["Next"].tap()
    }
}


extension XCUIApplication {
    func assertShareSheetTextElementExists(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let exists = self.staticTexts[text].waitForExistence(timeout: 2) || self.otherElements[text].waitForExistence(timeout: 2)
        XCTAssert(exists, file: file, line: line)
    }
}


extension XCUIElement {
    func toggleSwitch(file: StaticString = #filePath, line: UInt = #line) throws {
        #if os(visionOS)
        let value = switch try XCTUnwrap(value as? String, file: file, line: line) {
        case "0":
            false
        case "1":
            true
        case let rawValue:
            throw NSError(domain: "edu.stanford.SpezOnboarding.UITests", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected switch value: '\(rawValue)'"
            ])
        }
        if value {
            swipeLeft()
        } else {
            swipeRight()
        }
        #else
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        }
        #endif
    }
}


func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}
