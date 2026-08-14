//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


class BluetoothViewsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
    }

    @MainActor
    func testBluetoothUnavailableViews() async throws {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Views"]))
        app.buttons["Views"].tap()

        func navigateUnavailableView(name: String, expected: String?, back: Bool = true) {
            XCTAssert(app.buttons[name].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
            app.buttons[name].tap()
            if let expected {
                XCTAssert(app.staticTexts[expected].waitForExistence(timeout: 2.0))
            }
            if back {
                XCTAssert(app.navigationBars.buttons["Views"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
                app.navigationBars.buttons["Views"].tap()
            }
        }

        navigateUnavailableView(name: "Bluetooth Powered On", expected: nil)
        navigateUnavailableView(name: "Bluetooth Unauthorized", expected: "Bluetooth Prohibited")
        navigateUnavailableView(name: "Bluetooth Unsupported", expected: "Bluetooth Unsupported")
        navigateUnavailableView(name: "Bluetooth Unknown", expected: "Bluetooth Failure")
        navigateUnavailableView(name: "Bluetooth Powered Off", expected: "Bluetooth Off", back: false)

        XCTAssert(app.buttons["Open Settings"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Open Settings"].tap()

        let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        // every following test assumes the app under test is frontmost again
        addTeardownBlock { @MainActor in
            settingsApp.terminate()
            app.activate()
        }
        XCTAssertTrue(settingsApp.wait(for: .runningForeground, timeout: 30.0))
    }

    @MainActor
    func testNearbyDeviceRow() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Views"]))
        app.buttons["Views"].tap()

        if ProcessInfo().operatingSystemVersion.majorVersion >= 26 {
            XCTAssert(app.staticTexts["Devices"].waitForExistence(timeout: 2.0))
        } else {
            XCTAssert(app.staticTexts["DEVICES"].waitForExistence(timeout: 2.0))
        }

        XCTAssert(app.staticTexts["Mock Device"].waitForExistence(timeout: 2.0))
        app.staticTexts["Mock Device"].tap()

        XCTAssert(app.buttons["Mock Device, Connected"].waitForExistence(timeout: 5.0))
        XCTAssert(app.buttons["Device Details"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Device Details"].tap()

        XCTAssert(app.navigationBars.staticTexts["Mock Device"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Name, Mock Device"].exists)
        XCTAssert(app.staticTexts["Model, MD1"].exists)
        XCTAssert(app.staticTexts["Firmware Version, 1.0"].exists)
        XCTAssert(app.staticTexts["Battery, 85 %"].exists)
    }
}
