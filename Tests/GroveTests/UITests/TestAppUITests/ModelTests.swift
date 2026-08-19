//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class ModelTests: XCTestCase {
    @MainActor
    func testModelPropertyWrapper() throws {
        let app = XCUIApplication()
        let modelButton = app.buttons["Model"]
        XCTAssertTrue(app.launchAndWait(for: modelButton))
        modelButton.tap()

        XCTAssert(app.staticTexts["Passed"].waitForExistence(timeout: 15))
    }
}
