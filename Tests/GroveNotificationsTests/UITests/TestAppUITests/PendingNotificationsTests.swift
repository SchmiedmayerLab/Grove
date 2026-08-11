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


final class PendingNotificationsTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPendingNotifications() { // swiftlint:disable:this function_body_length
        func navigateToTab(_ tabName: String, line: UInt = #line) {
            #if os(visionOS)
            XCTAssert(app.buttons[tabName].exists, line: line)
            app.buttons[tabName].firstMatch.tap()
            usleep(500000)
            app.buttons[tabName].firstMatch.tap()
            #else
            XCTAssert(app.tabBars.buttons[tabName].exists, line: line)
            app.tabBars.buttons[tabName].tap()
            usleep(500000)
            app.tabBars.buttons[tabName].tap()
            #endif
        }
        
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        XCTAssert(app.navigationBars.staticTexts["Notifications"].waitForExistence(timeout: 2.0))

        XCTAssert(app.staticTexts["Authorization, notDetermined"].exists)
        XCTAssert(app.buttons["Schedule Notifications"].exists)
        app.buttons["Schedule Notifications"].tap()

        XCTAssert(app.staticTexts["Authorization, provisional"].waitForExistence(timeout: 0.5))

        navigateToTab("Notifications")

        XCTAssert(app.navigationBars.staticTexts["Pending Notifications"].waitForExistence(timeout: 2.0))

        XCTAssert(app.staticTexts["Calendar Notification"].exists)
        XCTAssert(app.staticTexts["Interval Notification"].exists)

        app.staticTexts["Calendar Notification"].tap()
        XCTAssert(app.navigationBars.staticTexts["Calendar Notification"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            identifier: "calendar-request",
            title: "Calendar Notification",
            subtitle: "Test Notification",
            body: "This is a calendar notification",
            category: "calendar-test-notification",
            thread: "GroveNotifications",
            sound: true,
            interruption: .timeSensitive,
            type: "Calendar"
        )
        XCTAssert(app.navigationBars.buttons["Pending Notifications"].exists)
        app.navigationBars.buttons["Pending Notifications"].tap()

        XCTAssert(app.staticTexts["Interval Notification"].waitForExistence(timeout: 2.0))
        app.staticTexts["Interval Notification"].tap()
        XCTAssert(app.navigationBars.staticTexts["Interval Notification"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            identifier: "interval-request",
            title: "Interval Notification",
            subtitle: "Test Notification",
            body: "This is a interval notification",
            category: "interval-test-notification",
            thread: "GroveNotifications",
            sound: true,
            interruption: .critical,
            type: "Interval"
        )
        
        // Test cancellation
        
        navigateToTab("Controls")
        
        XCTAssert(app.buttons["Cancel Pending Notifications"].waitForExistence(timeout: 1))
        app.buttons["Cancel Pending Notifications"].tap()
        
        navigateToTab("Notifications")
        
        XCTAssertFalse(app.staticTexts["Calendar Notification"].exists)
        XCTAssertFalse(app.staticTexts["Interval Notification"].exists)
    }
}
