//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


public import XCTest

extension XCTestCase {
    /// Walks through the Health App onboarding flow, if necessary.
    @MainActor
    public func handleHealthAppOnboardingIfNecessary(_ healthApp: XCUIApplication = .healthApp) {
        // The notifications alert can interrupt at any point of the flow, including the recursive retry, so the
        // monitor has to outlive the whole thing rather than a single pass over it.
        let monitor = installHealthAppNotificationsAlertMonitor()
        defer {
            removeUIInterruptionMonitor(monitor)
        }
        if healthApp.staticTexts["Welcome to Health"].waitForExistence(timeout: 3) {
            handleOnboarding(healthApp)
        }
    }

    @MainActor
    func handleOnboarding(_ healthApp: XCUIApplication = .healthApp, alreadyRecursive: Bool = false) {
        if healthApp.staticTexts["Welcome to Health"].waitForExistence(timeout: 5) {
            let continueText = healthApp.staticTexts["Continue"]
            XCTAssertTrue(continueText.wait(for: \.isHittable, toEqual: true, timeout: 5))
            continueText.tap()

            XCTAssertTrue(continueText.wait(for: \.isHittable, toEqual: true, timeout: 5))
            continueText.tap()

            XCTAssertTrue(healthApp.buttons["Next"].wait(for: \.isHittable, toEqual: true, timeout: 5))
            healthApp.buttons["Next"].tap()

            // Sometimes the HealthApp fails to advance to the next step here.
            // Go back and try again.
            if !continueText.waitForExistence(timeout: 60) {
                // Go one step back.
                let backButton = healthApp.navigationBars["WDBuddyFlowUserInfoView"].buttons["Back"]
                XCTAssertTrue(backButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
                backButton.tap()

                XCTAssertTrue(continueText.wait(for: \.isHittable, toEqual: true, timeout: 5))
                continueText.tap()

                // Check if the Next button exists or of the view is still in a loading process.
                if healthApp.tables.buttons["Next"].wait(for: \.isHittable, toEqual: true, timeout: 5) {
                    healthApp.tables.buttons["Next"].tap()
                }

                // Continue button still doesn't exist, go for terminating the app.
                if !continueText.waitForExistence(timeout: 60) {
                    if alreadyRecursive {
                        logger.notice("Even the recursive process did fail. Terminate the process.")
                    }

                    healthApp.terminate()
                    healthApp.activate()
                    XCTAssertTrue(healthApp.wait(for: .runningForeground, timeout: 30))
                    handleOnboarding(healthApp, alreadyRecursive: true)
                    return
                }
            }

            // Try to turn off the Health Notifications Trends Switch:
            let trendsSwitch = healthApp.switches.firstMatch
            if trendsSwitch.wait(for: \.isHittable, toEqual: true, timeout: 5) {
                trendsSwitch.tap()
            }

            XCTAssertTrue(continueText.wait(for: \.isHittable, toEqual: true, timeout: 5))
            continueText.tap()

            // Unfortunately it seems like the UInterruptionMonitor does not catch the alert here.
            // Therefore, we have to manually see if it shows up here ...
            let allowNotificationsButton = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
            if allowNotificationsButton.wait(for: \.isHittable, toEqual: true, timeout: 5) {
                allowNotificationsButton.tap()
                XCTAssertTrue(allowNotificationsButton.waitForNonExistence(timeout: 10))
            }
        }
    }
    
    
    /// Installs a UI interruption monitor which will dismiss the "Health would like to send you notifications" alert.
    @discardableResult
    public func installHealthAppNotificationsAlertMonitor() -> any NSObjectProtocol {
        self.addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            MainActor.assumeIsolated {
                guard alert.staticTexts["“Health” Would Like to Send You Notifications"].exists else {
                    // Not the Health app's Notification request alert.
                    print(
                        """
                        Got an UIInterruptionMonitor alert that is not from the Health App:
                        \(alert.staticTexts)
                        """
                    )
                    return false
                }
                guard alert.buttons["Allow"].exists else {
                    XCTFail("Failed not dismiss alert: \(alert.staticTexts.allElementsBoundByIndex)")
                    return false
                }
                alert.buttons["Allow"].tap()
                return true
            }
        }
    }
}
