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
            let tab = app.buttons[tabName].firstMatch
            #else
            let tab = app.tabBars.buttons[tabName]
            #endif
            XCTAssert(tab.wait(for: \.isHittable, toEqual: true, timeout: 10), line: line)
            tab.tap()
            // The second tap pops the tab back to its root; the pause keeps the two taps from coalescing into a double tap.
            usleep(500000)
            tab.tap()
        }

        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        XCTAssert(app.navigationBars.staticTexts["Notifications"].waitForExistence(timeout: 15))

        // The navigation title renders on the first pass, the status label only once the view's task has
        // read the authorization status, so the label needs a wait of its own.
        XCTAssert(app.staticTexts["Authorization, notDetermined"].waitForExistence(timeout: 15))
        XCTAssert(app.buttons["Schedule Notifications"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Schedule Notifications"].tap()

        XCTAssert(app.staticTexts["Authorization, provisional"].waitForExistence(timeout: 15))

        navigateToTab("Notifications")

        XCTAssert(app.navigationBars.staticTexts["Pending Notifications"].waitForExistence(timeout: 5))

        // The list is filled by the view's task, so the rows arrive after the navigation title.
        XCTAssert(app.staticTexts["Calendar Notification"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Interval Notification"].exists)

        XCTAssert(app.staticTexts["Calendar Notification"].wait(for: \.isHittable, toEqual: true, timeout: 5))
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
        XCTAssert(app.navigationBars.buttons["Pending Notifications"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.navigationBars.buttons["Pending Notifications"].tap()

        XCTAssert(app.staticTexts["Interval Notification"].wait(for: \.isHittable, toEqual: true, timeout: 5))
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
        
        XCTAssert(app.buttons["Cancel Pending Notifications"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Cancel Pending Notifications"].tap()

        navigateToTab("Notifications")

        // Removing the requests and reloading the list both happen asynchronously, so the rows disappear after the tab switch.
        XCTAssert(app.staticTexts["Calendar Notification"].waitForNonExistence(timeout: 10))
        XCTAssert(app.staticTexts["Interval Notification"].waitForNonExistence(timeout: 10))
    }
}
