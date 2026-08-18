//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import XCTest


extension XCUIApplication {
    /// The bundle identifier for the home screen for the specific platform.
    ///
    /// E.g., `com.apple.springboard` on iOS.
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    public static var homeScreenBundle: String {
        #if os(visionOS)
        "com.apple.RealityLauncher"
        #elseif os(tvOS)
        "com.apple.pineboard"
        #elseif os(iOS)
        "com.apple.springboard"
        #else
        preconditionFailure("Unsupported platform.")
        #endif
    }
    
    private static var visionOS2: Bool {
        #if os(visionOS)
        if #available(visionOS 2.0, *) {
            true
        } else {
            false
        }
        #else
        false
        #endif
    }

    /// Deletes the application from the iOS springboard (iOS home screen) and launches it after it has been deleted and reinstalled.
    /// - Parameter appName: The name of the application as displayed on the springboard (iOS home screen).
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    public func deleteAndLaunch(withSpringboardAppName appName: String) {
        self.delete(app: appName)
        XCTAssert(self.launchAndWait(), "The app did not come up after being reinstalled.")
    }
    
    /// Delete the application from the home screen.
    ///
    /// Deletes the application from the iOS Springboard, visionOS RealityLauncher or tvOS Pineboard.
    /// - Parameter appName: The springboard name of the application.
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    public func delete(app appName: String) { // swiftlint:disable:this function_body_length cyclomatic_complexity
        self.terminate()

        let springboard = XCUIApplication(bundleIdentifier: Self.homeScreenBundle)
        
        #if os(visionOS)
        springboard.launch() // springboard is in `runningBackgroundSuspended` state on visionOS. So we need to launch it not just activate
        #else
        springboard.activate()
        #endif
        
        let homeScreenIcons = springboard.otherElements["Home screen icons"].icons

        func visibleIcon(named name: String) -> XCUIElement? {
            homeScreenIcons.matching(identifier: name).allElementsBoundByIndex.first { icon in
                let frame = icon.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                return icon.isHittable && !frame.isEmpty && !frame.isNull && springboard.frame.contains(center)
            }
        }

        func waitForVisibleIcon(named name: String, timeout: TimeInterval = 1) -> XCUIElement? {
            var icon = visibleIcon(named: name)
            guard icon == nil else {
                return icon
            }
            let predicate = NSPredicate { _, _ in
                icon = visibleIcon(named: name)
                return icon != nil
            }
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: springboard)
            _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
            return icon
        }

        // There might be multiple apps installed with the same name (e.g., we use "TestApp" a lot), so delete all of them
        while homeScreenIcons[appName].firstMatch.waitForExistence(timeout: 10.0) {
            // The icon can be several pages in: every package's UI tests install a target called
            // "TestApp", so a device that has run more than one of them has several to page past.
            // One swipe only reaches page two. An app that is genuinely absent or unreachable still fails.
            var swipes = 0
            var icon = waitForVisibleIcon(named: appName)
            while icon == nil && swipes < 10 {
                springboard.swipeLeft()
                swipes += 1
                icon = waitForVisibleIcon(named: appName)
            }

            guard let icon else {
                XCTFail("Unable to find a visible \(appName) icon after \(swipes) home-screen swipes.")
                return
            }
            #if os(visionOS)
            icon.press(forDuration: 1)
            #else
            icon.press(forDuration: 1.5)
            #endif
            
            if XCUIApplication.visionOS2 {
                // VisionOS 2.0 changed the behavior how apps are deleted, showing a delete button above the app icon.
                let deleteButton = homeScreenIcons[appName].buttons["Delete"]
                XCTAssert(deleteButton.waitForExistence(timeout: 5.0))
                deleteButton.tap()
            } else { // iPhone / iPad / visionOS 1
                if !springboard.collectionViews.buttons["Remove App"].waitForExistence(timeout: 5) {
                    if springboard.state != .runningForeground {
                        // The long press did not work, let's launch the springboard again and then try long pressing the app icon again.
                        springboard.activate()
                        XCTAssert(springboard.wait(for: .runningForeground, timeout: 2.0))
                        XCTAssert(icon.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
                        icon.press(forDuration: 1.75)
                    }
                    if springboard.collectionViews.buttons["Options"].exists {
                        // We long-pressed the app icon, and the "Remove App" button isn't showing up, but an "Options" button is.
                        // Sometimes, for reasons probably not known to anyone, the home screen will put the "Remove App" button into
                        // an "Options" submenu, instead of placing it in the root of the menu.
                        // So we first need to navigate to that submenu, and then try again
                        springboard.collectionViews.buttons["Options"].tap()
                        XCTAssert(springboard.buttons["Remove App"].waitForExistence(timeout: 5))
                    }
                }
                guard springboard.buttons["Remove App"].waitForExistence(timeout: 2) else {
                    XCTFail("The context menu for \(appName) never appeared.")
                    return
                }
                springboard.buttons["Remove App"].tap()
            }

            #if os(visionOS)
            // alerts are running in their own process on visionOS (lol). Took me literally 3 hours.
            let notifications = visionOSNotifications

            XCTAssert(notifications.staticTexts["Delete “\(appName)”?"].waitForExistence(timeout: 5.0))
            XCTAssert(notifications.buttons["Delete"].waitForExistence(timeout: 2.0))
            notifications.buttons["Delete"].tap() // currently no better way of hitting some "random" delete button.
            #else
            XCTAssert(springboard.alerts["Remove “\(appName)”?"].buttons["Delete App"].waitForExistence(timeout: 10.0))
            springboard.alerts["Remove “\(appName)”?"].buttons["Delete App"].tap()
            XCTAssert(springboard.alerts["Delete “\(appName)”?"].buttons["Delete"].waitForExistence(timeout: 10.0))
            springboard.alerts["Delete “\(appName)”?"].buttons["Delete"].tap()
            #endif

            // Deleting an app that stored health data puts up a blocking alert, and the icon only disappears
            // once it is dismissed. Watching for both at once means a delete without the alert costs nothing,
            // while a slow alert still gets the full budget.
            let healthAlert = springboard.alerts["There is data from “\(appName)” saved in Health"]
            let deadline = Date.now.addingTimeInterval(15.0)
            var removed = false
            repeat {
                if healthAlert.exists {
                    healthAlert.buttons["OK"].tap()
                }
                removed = !icon.exists
            } while !removed && Date.now < deadline

            if removed {
                break
            }
        }
    }
}
