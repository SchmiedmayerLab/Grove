//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
@testable import XCTestExtensions


@MainActor
class OtherTests: XCTestCase {
    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    func testToggleStuff() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 2))
        app.buttons["Toggles / Switches"].tap()
        
        XCTAssert(app.navigationBars["Toggles / Switches"].waitForExistence(timeout: 1))
        print(app.debugDescription)
        
        let toggle = app.switches["Selection"]
        
        func assertToggleState(_ expectedState: Bool, line: UInt = #line) {
            XCTAssert(app.staticTexts["Selection Value, \(expectedState)"].waitForExistence(timeout: 1))
            XCTAssertEqual(toggle.toggleState, expectedState)
        }
        
        assertToggleState(false)
        try toggle.flipToggle()
        assertToggleState(true)
        try toggle.setToggleState(isOn: true)
        assertToggleState(true)
        try toggle.setToggleState(isOn: true)
        assertToggleState(true)
        try toggle.setToggleState(isOn: false)
        assertToggleState(false)
        try toggle.flipToggle()
        assertToggleState(true)
        try toggle.flipToggle()
        assertToggleState(false)
        try toggle.setToggleState(isOn: true)
        assertToggleState(true)
    }
}
