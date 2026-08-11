//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


@MainActor
class XCTestAppTests: XCTestCase {
    func testTestAppTestCaseTest() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.buttons["XCTestApp"].waitForExistence(timeout: 2.0))
        app.buttons["XCTestApp"].tap()

        XCTAssert(app.navigationBars.staticTexts["XCTestApp"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Passed"].waitForExistence(timeout: 5.0))
    }
}
