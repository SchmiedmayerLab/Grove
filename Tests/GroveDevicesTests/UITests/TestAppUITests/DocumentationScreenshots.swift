//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: resources Sources/GroveDevicesUI/GroveDevicesUI.docc/Resources
// documentation-screenshots: copy PairedDevices Sources/Grove/Grove.docc/Resources/PairedDevices.png

/// Walks pairing, the device list, a device's details and a recorded measurement; run through
/// `Scripts/documentation-screenshots.sh`.
final class DocumentationScreenshots: XCTestCase {
    override func setUpWithError() throws {
        // The walk needs the app the script launched and the states it prepared; a plain test run skips it.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GROVE_DOCUMENTATION_SCREENSHOTS"] == "1",
            "Run through Scripts/documentation-screenshots.sh"
        )
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureDocumentationScreenshots() throws {
        let app = XCUIApplication()
        if app.state != .runningForeground {
            app.activate()
        }
        sleep(1)
        app.buttons["Devices"].tap()
        XCTAssert(app.staticTexts["No Devices"].waitForExistence(timeout: 5))

        pair(app, menu: ["Omron Devices", "Discover Weight Scale"])
        pair(app, menu: ["Omron Devices", "Discover Blood Pressure Cuff", "BP 5250"])
        pair(app, menu: ["Omron Devices", "Discover Blood Pressure Cuff", "BP 7000"], captureAs: "Pairing")
        sleep(2)
        capture("PairedDevices")

        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BP5250'")).firstMatch
        XCTAssert(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssert(app.navigationBars.staticTexts["Device Details"].waitForExistence(timeout: 3))
        sleep(2)
        capture("DeviceDetails")
        app.navigationBars.buttons["Devices"].tap()

        app.buttons["Measurements"].tap()
        XCTAssert(app.navigationBars.buttons["More"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Hide Unavailable View"].waitForExistence(timeout: 3))
        app.buttons["Hide Unavailable View"].tap()
        sleep(1)
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Simulate Blood Pressure"].waitForExistence(timeout: 3))
        app.buttons["Simulate Blood Pressure"].tap()
        XCTAssert(app.staticTexts["Measurement Recorded"].waitForExistence(timeout: 5))
        sleep(2)
        capture("MeasurementRecorded")
    }

    /// Discovers a simulated device through the test app's menu and pairs it, capturing the pairing sheet when asked.
    @MainActor
    private func pair(_ app: XCUIApplication, menu: [String], captureAs name: String? = nil) {
        XCTAssert(app.navigationBars.buttons["More"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["More"].tap()
        for item in menu {
            XCTAssert(app.buttons[item].waitForExistence(timeout: 3))
            app.buttons[item].tap()
        }
        if !app.staticTexts["Pair Accessory"].waitForExistence(timeout: 2) {
            app.navigationBars.buttons["Add Device"].tap()
            XCTAssert(app.staticTexts["Pair Accessory"].waitForExistence(timeout: 10))
        }
        if let name {
            sleep(2)
            capture(name)
        }
        app.buttons["Pair"].tap()
        XCTAssert(app.staticTexts["Accessory Paired"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        sleep(2)
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
