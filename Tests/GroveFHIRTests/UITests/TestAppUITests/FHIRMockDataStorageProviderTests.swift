//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTest
import XCTestExtensions


final class GroveFHIRTests: XCTestCase {
    func testMockPatientResources() throws {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Select Mock Patient"]))

        XCTAssert(app.staticTexts["Allergy Intolerances, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Conditions, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Diagnostics, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Documents, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Encounters, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Immunizations, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Medications, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Observations, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Procedures, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Other Resources, 0"].waitForExistence(timeout: 2))

        app.selectMockPatient("Jamison785 Denesik803")

        XCTAssert(app.staticTexts["Allergy Intolerances, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Conditions, 70"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Diagnostics, 205"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Documents, 82"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Encounters, 82"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Immunizations, 12"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Medications, 31"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Observations, 769"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Procedures, 106"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Other Resources, 220"].waitForExistence(timeout: 2))

        app.selectMockPatient("Maye976 Dickinson688")

        XCTAssert(app.staticTexts["Allergy Intolerances, 0"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Conditions, 37"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Diagnostics, 113"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Documents, 86"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Encounters, 86"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Immunizations, 11"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Medications, 55"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Observations, 169"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Procedures, 225"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Other Resources, 236"].waitForExistence(timeout: 2))
    }


    @MainActor
    func testAddingAndRemovingResources() throws {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Add FHIR Resource"]))

        // Add 5 resources
        for resourceCount in 0..<5 {
            XCTAssert(app.staticTexts["Other Resources, \(resourceCount)"].waitForExistence(timeout: 2))
            XCTAssert(app.buttons["Add FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
            app.buttons["Add FHIR Resource"].tap()
        }

        // Remove added resources
        XCTAssert(app.buttons["Remove FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Remove FHIR Resource"].tap()

        XCTAssert(app.staticTexts["Other Resources, 0"].waitForExistence(timeout: 2))

        // Try removing a second time
        XCTAssert(app.buttons["Remove FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Remove FHIR Resource"].tap()

        XCTAssert(app.staticTexts["Other Resources, 0"].waitForExistence(timeout: 2))

        app.selectMockPatient("Jamison785 Denesik803")

        XCTAssert(app.staticTexts["Other Resources, 220"].waitForExistence(timeout: 2))

        // Add resource to mock patient
        XCTAssert(app.buttons["Add FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Add FHIR Resource"].tap()

        XCTAssert(app.staticTexts["Other Resources, 221"].waitForExistence(timeout: 2))

        // Remove resource from mock patient
        XCTAssert(app.buttons["Remove FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Remove FHIR Resource"].tap()

        XCTAssert(app.staticTexts["Other Resources, 220"].waitForExistence(timeout: 2))

        // Try removing a second time
        XCTAssert(app.buttons["Remove FHIR Resource"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Remove FHIR Resource"].tap()

        XCTAssert(app.staticTexts["Other Resources, 220"].waitForExistence(timeout: 2))
    }
}


extension XCUIApplication {
    fileprivate func selectMockPatient(_ name: String, timeout: TimeInterval = 20) {
        XCTAssert(buttons["Select Mock Patient"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        buttons["Select Mock Patient"].tap()

        // The sheet decodes every mock bundle before it lists the patients, which takes a while.
        XCTAssert(buttons[name].wait(for: \.isHittable, toEqual: true, timeout: timeout))
        buttons[name].tap()

        let close = navigationBars["Select Mock Patient"].buttons["Close Mock Patient Selection"]
        XCTAssert(close.wait(for: \.isHittable, toEqual: true, timeout: timeout))
        close.tap()
        XCTAssert(navigationBars["Select Mock Patient"].waitForNonExistence(timeout: 5))
    }
}
