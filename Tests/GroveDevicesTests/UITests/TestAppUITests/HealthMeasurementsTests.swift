//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


class HealthMeasurementsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
    }
    
    
    @MainActor
    func testNoMeasurements() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Measurements"]))
        app.buttons["Measurements"].tap()

        XCTAssert(app.staticTexts["No Samples"].waitForExistence(timeout: 2.0))
        app.staticTexts["No Samples"].tap()

        XCTAssert(app.navigationBars.buttons["Add Measurement"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Add Measurement"].tap()

        XCTAssert(app.staticTexts["No Pending Measurements"].waitForExistence(timeout: 2.0))
        XCTAssert(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()
    }

    @MainActor
    func testWeightMeasurement() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Measurements"]))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Weight"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Simulate Weight"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["42 kg"].exists)
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        XCTAssert(app.buttons["Save"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Save"].tap()

        // the sheet dismisses and the samples show up only once they were written to HealthKit
        XCTAssert(app.staticTexts["Measurement Recorded"].waitForNonExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["42 kg"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["23 count"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["1.79 m"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["Mock Device"].waitForExistence(timeout: 5.0))
    }

    @MainActor
    func testBloodPressureMeasurement() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Measurements"]))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Blood Pressure"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Simulate Blood Pressure"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["103/64 mmHg"].exists)
        XCTAssert(app.staticTexts["62 BPM"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        XCTAssert(app.buttons["Save"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Save"].tap()

        // the sheet dismisses and the samples show up only once they were written to HealthKit
        XCTAssert(app.staticTexts["Measurement Recorded"].waitForNonExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["103 mmHg"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["64 mmHg"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["62 count/min"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["Mock Device"].waitForExistence(timeout: 5.0))
    }

    @MainActor
    func testMultiMeasurementsAndDiscarding() throws { // swiftlint:disable:this function_body_length
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Measurements"]))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Weight"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Simulate Weight"].tap()

        XCTAssert(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Blood Pressure"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Simulate Blood Pressure"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["103/64 mmHg"].exists)
        XCTAssert(app.staticTexts["62 BPM"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        let pageIndicator = app.pageIndicators.firstMatch
        XCTAssert(pageIndicator.waitForExistence(timeout: 2.0))
        let page1Value = try XCTUnwrap(pageIndicator.value as? String, "Unexpected value \(String(describing: pageIndicator.value))")
        XCTAssertEqual(page1Value, "page 1 of 2")
        pageIndicator.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.5)).tap()
        let secondPage = expectation(for: NSPredicate(format: "value == 'page 2 of 2'"), evaluatedWith: pageIndicator)
        wait(for: [secondPage], timeout: 2.0)

        XCTAssert(app.staticTexts["42 kg"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Measurement Recorded"].exists)
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        XCTAssert(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssert(app.navigationBars.buttons["Add Measurement"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Add Measurement"].tap()

        XCTAssert(app.buttons["Discard"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Discard"].tap()

        XCTAssert(app.staticTexts["42 kg"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)

        XCTAssert(app.buttons["Discard"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Discard"].tap()
    }
}
