//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
        
        let app = XCUIApplication()
        
        #if !os(macOS)
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        #else
        app.launch()
        #endif
    }
    
    func testRequestPermissions() throws {
        let app = XCUIApplication()
        
        XCTAssert(app.staticTexts["Location not available"].waitForExistence(timeout: 3))
        
        XCTAssert(app.buttons["Request When In Use Permission"].waitForExistence(timeout: 3))
        app.buttons["Request When In Use Permission"].tap()
        
        let springboard = XCUIApplication(bundleIdentifier: XCUIApplication.homeScreenBundle)

        let allowButton = springboard.buttons["Allow While Using App"]
        XCTAssert(allowButton.waitForExistence(timeout: 30), "Location permission alert did not appear")
        allowButton.tap()
        XCTAssert(allowButton.waitForNonExistence(timeout: 10), "Location permission alert did not dismiss")

        XCTAssert(app.staticTexts["Authorization Status: Authorized when in use"].waitForExistence(timeout: 10))
    }
}
