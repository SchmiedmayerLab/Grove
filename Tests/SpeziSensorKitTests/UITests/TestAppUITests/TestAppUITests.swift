//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OSLog
import XCTest


class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    @MainActor
    func testSpeziSensorKit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.staticTexts["Hello Spezi :)"].waitForExistence(timeout: 1))
    }
}
