//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import GroveNotifications
import UserNotifications
public import XCTest


extension XCUIApplication {
    /// Action of the notification authorization alert.
    public enum NotificationAuthorizationAction: String {
        case allow = "Allow"
        case doNotAllow = "Don’t Allow"
    }
    
    /// Confirm the notification authorization dialog.
    ///
    /// - parameter action: The action to respond with in the alert.
    /// - parameter timeout: How long to wait for the alert to appear.
    /// - parameter requireAlertToAppear: Whether the alert not appearing within `timeout` should be considered as a test failure.
    ///     Setting this option to `false` will result in the function simply returning and tests continuing without issue,
    ///     if the alert does not appear, e.g. because it already was responded to in the past.
    ///     Defaults to `false`.
    /// - returns: A boolean value indicating whether the alert appeared.
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    @discardableResult
    public func confirmNotificationAuthorization(
        action: NotificationAuthorizationAction = .allow,
        timeout: TimeInterval = 5,
        requireAlertToAppear: Bool = false
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS 'Would Like to Send You Notifications'")
        #if os(iOS)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.element(matching: predicate)
        if alert.waitForExistence(timeout: timeout) {
            XCTAssert(alert.buttons[action.rawValue].exists)
            alert.buttons[action.rawValue].tap()
            return true
        } else if requireAlertToAppear {
            // the alert is required to appear within `timeout`, but didn't
            XCTFail("Notification permissions alert did not appear.")
        }
        return false
        #elseif os(visionOS)
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.RealityNotifications")
        if notifications.scrollViews.staticTexts.element(matching: predicate).waitForExistence(timeout: timeout) {
            XCTAssert(notifications.buttons[action.rawValue].exists)
            notifications.buttons[action.rawValue].tap()
            return true
        } else if requireAlertToAppear {
            // the alert is required to appear within `timeout`, but didn't
            XCTFail("Notification permissions alert did not appear.")
        }
        return false
        #endif
    }
}
