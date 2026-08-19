//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


class PairedDevicesTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
    }

    @MainActor
    func testTipsView() {
        let app = XCUIApplication()
        app.launchArguments = ["--testTips"]
        XCTAssert(app.launchAndWait(for: app.buttons["Devices"]))
        app.buttons["Devices"].tap()


        XCTAssert(app.staticTexts["Fully Unpair Device"].waitForExistence(timeout: 2.0))
        XCTAssert(app.buttons["Open Settings"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Open Settings"].tap()

        let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        // every following test assumes the app under test is frontmost again
        addTeardownBlock { @MainActor in
            settingsApp.terminate()
            app.activate()
        }
        XCTAssert(settingsApp.wait(for: .runningForeground, timeout: 30.0))
    }

    @MainActor
    func testDiscoveringView() throws {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Devices"]))
        app.buttons["Devices"].tap()


        XCTAssert(app.staticTexts["No Devices"].waitForExistence(timeout: 2.0))
        XCTAssert(app.buttons["Pair New Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Pair New Device"].tap()

        XCTAssert(app.staticTexts["Discovering"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Enable pairing mode on the device."].exists)
        XCTAssert(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssert(app.staticTexts["No Devices"].waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testPairDevice() throws { // swiftlint:disable:this function_body_length
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Devices"]))
        app.buttons["Devices"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()

        XCTAssert(app.buttons["Discover Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Discover Device"].tap()

        XCTAssert(app.buttons["Add Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Add Device"].tap()

        XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10.0))
        XCTAssert(app.staticTexts["Do you want to pair \"Mock Device\" with the Example app?"].exists)
        XCTAssert(app.buttons["Pair"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Pair"].tap()

        XCTAssert(app.staticTexts["Accessory Paired"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["\"Mock Device\" was successfully paired with the Example app."].exists)
        XCTAssert(app.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Done"].tap()

        XCTAssert(app.buttons["My Mock Device, 85 %"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["My Mock Device, 85 %"].tap()

        XCTAssert(app.navigationBars.staticTexts["Device Details"].waitForExistence(timeout: 2.0))
        XCTAssert(app.buttons["Name, My Mock Device"].exists)
        XCTAssert(app.staticTexts["Model, MD1"].exists)
        XCTAssert(app.staticTexts["Battery, 85 %"].exists)
        XCTAssert(app.buttons["Forget This Device"].exists)
        XCTAssert(app.staticTexts["Synchronizing ..."].waitForExistence(timeout: 2.0)) // assert device currently connected

        app.buttons["Name, My Mock Device"].tap()

        XCTAssert(app.textFields["enter device name"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.textFields["enter device name"].tap()
        app.typeText("2")

        app.dismissKeyboard()

        XCTAssert(app.navigationBars.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Done"].tap()

        XCTAssert(app.staticTexts["Name, My Mock Device2"].waitForExistence(timeout: 2.0))
        XCTAssert(app.navigationBars.buttons["Devices"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Devices"].tap()

        XCTAssert(app.buttons["My Mock Device2, 85 %"].waitForExistence(timeout: 2.0))

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Disconnect"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Disconnect"].tap()

        XCTAssert(app.buttons["My Mock Device2, 85 %"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["My Mock Device2, 85 %"].tap()
        XCTAssert(app.navigationBars.buttons["Devices"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Devices"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Connect"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Connect"].tap()

        XCTAssert(app.buttons["My Mock Device2, 85 %"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["My Mock Device2, 85 %"].tap()
        XCTAssert(app.staticTexts["Synchronizing ..."].waitForExistence(timeout: 5.0)) // assert device reconnected

        XCTAssert(app.buttons["Forget This Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Forget This Device"].tap()

        XCTAssert(app.buttons["Forget Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Forget Device"].tap()


        XCTAssert(app.staticTexts["Fully Unpair Device"].waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testPlusButton() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Devices"]))
        app.buttons["Devices"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()

        XCTAssert(app.buttons["Discover Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Discover Device"].tap()

        XCTAssert(app.buttons["Add Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Add Device"].tap()

        XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10.0))
        let closeButton = app.otherElements["AccessorySetupSheet"].navigationBars.buttons["Close"]
        XCTAssert(closeButton.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        closeButton.tap()

        XCTAssert(app.navigationBars.buttons["Add Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Add Device"].tap()

        XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10.0))
    }

    @MainActor
    func testPairingFailed() {
        let app = XCUIApplication()
        XCTAssert(app.launchAndWait(for: app.buttons["Devices"]))
        app.buttons["Devices"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Connect"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Connect"].tap()

        XCTAssert(app.navigationBars.buttons["More"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Discover Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Discover Device"].tap()

        XCTAssert(app.buttons["Add Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Add Device"].tap()

        XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10.0))
        XCTAssert(app.buttons["Pair"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Pair"].tap()

        XCTAssert(app.staticTexts["Pairing Failed"].waitForExistence(timeout: 5.0))
        XCTAssert(app.staticTexts["Failed to pair with device. Please try again."].exists)
        XCTAssert(app.buttons["OK"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["OK"].tap()

        XCTAssert(app.navigationBars.buttons["Add Device"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Add Device"].tap()

        XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10.0))
    }
}
