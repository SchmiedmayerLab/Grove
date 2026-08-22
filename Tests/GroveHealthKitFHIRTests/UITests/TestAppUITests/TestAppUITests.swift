//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTHealthKit


class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    
    @MainActor
    func testGroveHealthKitFHIR() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Write Data
        XCTAssert(app.collectionViews.buttons["Write Data"].waitForExistence(timeout: 5))
        app.collectionViews.buttons["Write Data"].tap()
        
        XCTAssert(app.collectionViews.textFields["Number of steps..."].waitForExistence(timeout: 5))
        try app.collectionViews.textFields["Number of steps..."].enter(value: "2")
        
        app.collectionViews.buttons["Write Step Count"].tap()
        
        // Enable Apple Health Access if needed
        app.handleHealthKitAuthorization()
        
        // Check that the data is written
        XCTAssert(app.collectionViews.staticTexts["Data successfully written!"].waitForExistence(timeout: 5))
        
        // Return back to the main view
        app.navigationBars.buttons["BackButton"].tap()
        
        // Check that the data can be read
        app.collectionViews.buttons["Read Data"].tap()
        app.collectionViews.buttons["Read Steps"].tap()
        
        // Dismiss results view
        app.swipeDown(velocity: XCUIGestureVelocity.fast)
    }

    @MainActor
    func testMappingCompleteness() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Mapping Completeness"].tap()
        // The catalog renders grouped by status, and the first group is the one the enum orders
        // first. Only the visible rows of a 218-row List exist in the accessibility tree, so this
        // asserts the first section rather than a row further down; the catalog's completeness is
        // proven exhaustively by the unit-test matrix instead.
        XCTAssertTrue(app.staticTexts["deferred"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Biological Sex"].waitForExistence(timeout: 5))
    }
}
