//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


class HealthMeasurementsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
    }
    
    
    @MainActor
    func testNoMeasurements() {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Measurements"].waitForExistence(timeout: 2.0))
        app.buttons["Measurements"].tap()

        XCTAssert(app.staticTexts["No Samples"].waitForExistence(timeout: 0.5))
        app.staticTexts["No Samples"].tap()

        XCTAssert(app.navigationBars.buttons["Add Measurement"].exists)
        app.navigationBars.buttons["Add Measurement"].tap()

        XCTAssert(app.staticTexts["No Pending Measurements"].waitForExistence(timeout: 2.0))
        XCTAssert(app.navigationBars.buttons["Close"].exists)
        app.navigationBars.buttons["Close"].tap()
    }

    @MainActor
    func testWeightMeasurement() {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Measurements"].waitForExistence(timeout: 2.0))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].exists)
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Weight"].waitForExistence(timeout: 0.5))
        app.buttons["Simulate Weight"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["42 kg"].exists)
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        app.buttons["Save"].tap()

        XCTAssert(app.staticTexts["42 kg"].waitForExistence(timeout: 0.5))
        XCTAssert(app.staticTexts["23 count"].exists)
        XCTAssert(app.staticTexts["1.79 m"].exists)
        XCTAssert(app.staticTexts["Mock Device"].exists)
    }

    @MainActor
    func testBloodPressureMeasurement() {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Measurements"].waitForExistence(timeout: 2.0))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].exists)
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Blood Pressure"].waitForExistence(timeout: 0.5))
        app.buttons["Simulate Blood Pressure"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["103/64 mmHg"].exists)
        XCTAssert(app.staticTexts["62 BPM"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        app.buttons["Save"].tap()

        XCTAssert(app.staticTexts["103 mmHg"].waitForExistence(timeout: 0.5))
        XCTAssert(app.staticTexts["64 mmHg"].exists)
        XCTAssert(app.staticTexts["62 count/min"].exists)
        XCTAssert(app.staticTexts["Mock Device"].exists)
    }

    @MainActor
    func testMultiMeasurementsAndDiscarding() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Measurements"].waitForExistence(timeout: 2.0))
        app.buttons["Measurements"].tap()

        XCTAssert(app.navigationBars.buttons["More"].exists)
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Weight"].waitForExistence(timeout: 0.5))
        app.buttons["Simulate Weight"].tap()

        XCTAssert(app.navigationBars.buttons["Close"].waitForExistence(timeout: 0.5))
        app.navigationBars.buttons["Close"].tap()

        XCTAssert(app.navigationBars.buttons["More"].exists)
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Blood Pressure"].waitForExistence(timeout: 0.5))
        app.buttons["Simulate Blood Pressure"].tap()

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["103/64 mmHg"].exists)
        XCTAssert(app.staticTexts["62 BPM"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        XCTAssert(app.pageIndicators.firstMatch.exists)
        let page1Value = try XCTUnwrap(app.pageIndicators.firstMatch.value as? String, "Unexpected value \(String(describing: app.steppers["Page"].value))")
        XCTAssertEqual(page1Value, "page 1 of 2")
        app.pageIndicators.firstMatch.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.5)).tap()
        let page2Value = try XCTUnwrap(app.pageIndicators.firstMatch.value as? String, "Unexpected value \(String(describing: app.steppers["Page"].value))")
        XCTAssertEqual(page2Value, "page 2 of 2")

        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["42 kg"].exists)
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)
        XCTAssert(app.buttons["Save"].exists)
        XCTAssert(app.buttons["Discard"].exists)

        XCTAssert(app.navigationBars.buttons["Close"].exists)
        app.navigationBars.buttons["Close"].tap()

        XCTAssert(app.navigationBars.buttons["Add Measurement"].waitForExistence(timeout: 0.5))
        app.navigationBars.buttons["Add Measurement"].tap()

        XCTAssert(app.buttons["Discard"].waitForExistence(timeout: 0.5))
        app.buttons["Discard"].tap()

        XCTAssert(app.staticTexts["42 kg"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["179 cm,  23 BMI"].exists)

        XCTAssert(app.buttons["Discard"].waitForExistence(timeout: 0.5))
        app.buttons["Discard"].tap()
    }
}
