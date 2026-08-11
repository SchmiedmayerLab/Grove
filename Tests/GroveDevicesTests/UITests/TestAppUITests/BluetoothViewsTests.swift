//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


class BluetoothViewsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
    }

    @MainActor
    func testBluetoothUnavailableViews() async throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Views"].waitForExistence(timeout: 2.0))
        app.buttons["Views"].tap()

        func navigateUnavailableView(name: String, expected: String?, back: Bool = true) {
            XCTAssert(app.buttons[name].waitForExistence(timeout: 2.0))
            app.buttons[name].tap()
            if let expected {
                XCTAssert(app.staticTexts[expected].waitForExistence(timeout: 2.0))
            }
            if back {
                XCTAssert(app.navigationBars.buttons["Views"].exists)
                app.navigationBars.buttons["Views"].tap()
            }
        }

        navigateUnavailableView(name: "Bluetooth Powered On", expected: nil)
        navigateUnavailableView(name: "Bluetooth Unauthorized", expected: "Bluetooth Prohibited")
        navigateUnavailableView(name: "Bluetooth Unsupported", expected: "Bluetooth Unsupported")
        navigateUnavailableView(name: "Bluetooth Unknown", expected: "Bluetooth Failure")
        navigateUnavailableView(name: "Bluetooth Powered Off", expected: "Bluetooth Off", back: false)

        XCTAssert(app.buttons["Open Settings"].exists)
        app.buttons["Open Settings"].tap()

        let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settingsApp.wait(for: .runningForeground, timeout: 2.0))
    }

    @MainActor
    func testNearbyDeviceRow() {
        let app = XCUIApplication()
        app.launch()

        XCTAssert(app.buttons["Views"].waitForExistence(timeout: 2.0))
        app.buttons["Views"].tap()

        if ProcessInfo().operatingSystemVersion.majorVersion >= 26 {
            XCTAssert(app.staticTexts["Devices"].exists)
        } else {
            XCTAssert(app.staticTexts["DEVICES"].exists)
        }

        XCTAssert(app.staticTexts["Mock Device"].exists)
        app.staticTexts["Mock Device"].tap()

        XCTAssert(app.buttons["Mock Device, Connected"].waitForExistence(timeout: 5.0))
        XCTAssert(app.buttons["Device Details"].exists)
        app.buttons["Device Details"].tap()

        XCTAssert(app.navigationBars.staticTexts["Mock Device"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Name, Mock Device"].exists)
        XCTAssert(app.staticTexts["Model, MD1"].exists)
        XCTAssert(app.staticTexts["Firmware Version, 1.0"].exists)
        XCTAssert(app.staticTexts["Battery, 85 %"].exists)
    }
}
