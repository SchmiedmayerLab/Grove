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
        XCTAssertTrue(app.launchAndWait(for: app.buttons["Register"]))

        XCTAssertTrue(app.navigationBars.staticTexts["Notifications"].exists)
        XCTAssertTrue(app.staticTexts["Token, none"].exists)
        XCTAssertTrue(app.buttons["Unregister"].exists)

        let tokenField = app.staticTexts.matching(identifier: "token-field").firstMatch
        app.buttons["Register"].tap()

        // Registration resolves asynchronously into either a token or an error, so wait for the field to leave its initial state
        // instead of racing one particular outcome.
        let registrationSettled = expectation(for: NSPredicate(format: "label != %@", "Token, none"), evaluatedWith: tokenField)
        wait(for: [registrationSettled], timeout: 30)

        XCTAssertFalse(app.staticTexts["Token, failed"].exists)
        XCTAssertTrue(
            app.staticTexts["Token, 80 bytes"].exists
                || app.staticTexts["Token, 60 bytes"].exists
                || app.staticTexts["Token, Timeout"].exists
        )

        // the unit test accepts both success and failure states. Therefore, print the content of the field to have it visible in the logs
        print("Read token field as: \(tokenField.debugDescription)")

        XCTAssertTrue(app.buttons["Unregister"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Unregister"].tap()
        XCTAssertTrue(app.staticTexts["Token, none"].waitForExistence(timeout: 5))
    }
}
