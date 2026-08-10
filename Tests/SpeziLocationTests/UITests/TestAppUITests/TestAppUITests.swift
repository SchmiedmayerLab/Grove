//
// This source file is part of the Stanford Spezi open-source project
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
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        if springboard.buttons["Allow While Using App"].waitForExistence(timeout: 10) {
            springboard.buttons["Allow While Using App"].tap()
        }
        
        XCTAssert(app.staticTexts["Authorization Status: Authorized when in use"].waitForExistence(timeout: 10))
    }
}
