//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class ViewModifierTests: XCTestCase {
    @MainActor
    func testViewModifierPropertyWrapper() throws {
        let app = XCUIApplication()
        let viewModifierButton = app.buttons["ViewModifier"]
        XCTAssertTrue(app.launchAndWait(for: viewModifierButton))
        viewModifierButton.tap()

        XCTAssertFalse(app.alerts["Test Failed"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Passed"].waitForExistence(timeout: 15))
    }
}
