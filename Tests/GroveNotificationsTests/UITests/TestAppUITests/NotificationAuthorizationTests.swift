//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveNotifications


final class NotificationAuthorizationTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNotificationAuthorizationAllow() {
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        XCTAssert(app.navigationBars.staticTexts["Notifications"].waitForExistence(timeout: 15))

        // The navigation title renders on the first pass, the status label only once the view's task has
        // read the authorization status, so the label needs a wait of its own.
        XCTAssert(app.staticTexts["Authorization, notDetermined"].waitForExistence(timeout: 15))
        XCTAssert(app.buttons["Request Authorization"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Request Authorization"].tap()

        app.confirmNotificationAuthorization(requireAlertToAppear: true)
        XCTAssert(app.staticTexts["Authorization, authorized"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testNotificationAuthorizationNotAllow() {
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        XCTAssert(app.navigationBars.staticTexts["Notifications"].waitForExistence(timeout: 15))

        XCTAssert(app.staticTexts["Authorization, notDetermined"].waitForExistence(timeout: 15))
        XCTAssert(app.buttons["Request Authorization"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Request Authorization"].tap()

        app.confirmNotificationAuthorization(action: .doNotAllow, requireAlertToAppear: true)

        XCTAssert(app.staticTexts["Authorization, denied"].waitForExistence(timeout: 15))
    }
    
    
    /// Tests that the `XCUIApplication.confirmNotificationAuthorization` function can be called multiple times,
    /// even if notification access has already been decided and no alert will show up.
    @MainActor
    func testNotificationAuthorizationAlreadyDecided() {
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        XCTAssert(app.navigationBars.staticTexts["Notifications"].waitForExistence(timeout: 15))
        
        XCTAssert(app.staticTexts["Authorization, notDetermined"].waitForExistence(timeout: 15))
        XCTAssert(app.buttons["Request Authorization"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Request Authorization"].tap()

        app.confirmNotificationAuthorization()
        XCTAssert(app.staticTexts["Authorization, authorized"].waitForExistence(timeout: 15))
        
        // simply run it again and implicitly check that it doesn't fail the test.
        app.confirmNotificationAuthorization()
        
        // check that requiring the alert to show up, when it won't, is a failure
        XCTExpectFailure {
            // an explicit short timeout keeps the negative path fast
            app.confirmNotificationAuthorization(timeout: 5, requireAlertToAppear: true)
        }
    }
}
