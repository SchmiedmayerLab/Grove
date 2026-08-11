//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class BluetoothManagerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
    }

    @MainActor
    func testGroveBluetooth() throws {
        let app = XCUIApplication()
        app.launch()
        
        XCTAssert(app.staticTexts["Grove Bluetooth"].waitForExistence(timeout: 2))

        XCTAssert(app.buttons["Nearby Devices"].exists)
        XCTAssert(app.buttons["Test Peripheral"].exists)

        app.buttons["Nearby Devices"].tap()

        XCTAssert(app.navigationBars.staticTexts["Nearby Devices"].waitForExistence(timeout: 2.0))
        try app.assertMinimalSimulatorInformation()

        sleep(10) // this goes through stale timer and everything!

        XCTAssert(app.navigationBars.buttons["Grove Bluetooth"].exists)
        app.navigationBars.buttons["Grove Bluetooth"].tap()
        sleep(3)
    }
}
