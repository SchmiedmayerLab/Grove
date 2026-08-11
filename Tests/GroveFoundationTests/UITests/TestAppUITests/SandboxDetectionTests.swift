//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTest
import XCTestExtensions


class SandboxDetectionTests: XCTestCase {
    @MainActor
    func testRuntimeContext() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 2))
        app.buttons["Sandbox Detection"].tap()
        XCTAssertTrue(app.staticTexts["Is running in Sandbox, true"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Is running in XCTest, false"].waitForExistence(timeout: 1))
    }
}
