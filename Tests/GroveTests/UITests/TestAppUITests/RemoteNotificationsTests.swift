//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class RemoteNotificationsTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRegistrationOnSimulator() throws {
        let app = XCUIApplication()
        let notificationsButton = app.buttons["Remote Notifications"]
        XCTAssertTrue(app.launchAndWait(for: notificationsButton))
        notificationsButton.tap()

        XCTAssertTrue(app.navigationBars["Remote Notifications"].waitForExistence(timeout: 5.0))
        let registerButton = app.buttons["Register"]
        XCTAssertTrue(registerButton.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        XCTAssertTrue(app.staticTexts["Token, none"].exists)
        XCTAssertTrue(app.buttons["Unregister"].exists)

        registerButton.tap()

        // Registration either hands back a token or fails after the five second registration timeout.
        let token = app.staticTexts.matching("label IN %@", ["Token, 80 bytes", "Token, 60 bytes"]).firstMatch
        if !token.waitForExistence(timeout: 10) {
            XCTAssertFalse(app.staticTexts["Token, failed"].exists)
            XCTAssertTrue(app.staticTexts["Token, Timeout"].exists)
        }

        // the unit test accepts both success and failure states. Therefore, print the content of the field to have it visible in the logs
        print("Read token field as: \(app.staticTexts.matching(identifier: "token-field").firstMatch.debugDescription)")

        let unregisterButton = app.buttons["Unregister"]
        XCTAssertTrue(unregisterButton.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        unregisterButton.tap()
        XCTAssertTrue(app.staticTexts["Token, none"].waitForExistence(timeout: 5.0))
    }
}
