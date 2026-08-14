//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class LifecycleHandlerTests: XCTestCase {
    @MainActor
    func testLifecycleHandler() throws {
        #if os(macOS) || os(watchOS)
            throw XCTSkip("LifecycleHandler is not supported on macOS or watchOS.")
        #endif

        let app = XCUIApplication()
        app.launchArguments = ["--lifecycleTests"]
        let lifecycleButton = app.buttons["LifecycleHandler"]
        XCTAssertTrue(app.launchAndWait(for: lifecycleButton))
        lifecycleButton.tap()

        // `SceneDidBecomeActive` is the last of the launch events, and all counters render from the same model.
        XCTAssert(app.staticTexts["SceneDidBecomeActive: 1"].waitForExistence(timeout: 15))
        XCTAssert(app.staticTexts["WillFinishLaunchingWithOptions: 1"].exists)
        XCTAssert(app.staticTexts["SceneWillEnterForeground: 1"].exists)
        XCTAssert(app.staticTexts["SceneWillResignActive: 0"].exists)
        XCTAssert(app.staticTexts["SceneDidEnterBackground: 0"].exists)
        XCTAssert(app.staticTexts["ApplicationWillTerminate: 0"].exists)


        #if os(visionOS)
        let chrome = XCUIApplication(bundleIdentifier: "com.apple.RealityChrome")
        let closeButton = chrome.buttons["CloseButton"]
        XCTAssert(closeButton.wait(for: \.isHittable, toEqual: true, timeout: 15))
        closeButton.tap()
        // A closed visionOS window lands in `.runningBackgroundSuspended` via `.runningBackground`, so no single state is waitable here.
        sleep(3)
        app.activate()
        #elseif !os(macOS)
        let homeScreen = XCUIApplication(bundleIdentifier: XCUIApplication.homeScreenBundle)
        homeScreen.activate()
        XCTAssertTrue(homeScreen.wait(for: .runningForeground, timeout: 15.0))
        app.activate()
        #endif

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15.0))

        XCTAssert(app.staticTexts["SceneDidBecomeActive: 2"].waitForExistence(timeout: 15))
        XCTAssert(app.staticTexts["WillFinishLaunchingWithOptions: 1"].exists)
        XCTAssert(app.staticTexts["SceneWillEnterForeground: 2"].exists)
        XCTAssert(app.staticTexts["SceneWillResignActive: 1"].exists)
        XCTAssert(app.staticTexts["SceneDidEnterBackground: 1"].exists)
        XCTAssert(app.staticTexts["ApplicationWillTerminate: 0"].exists)
    }

    @MainActor
    func testServiceModule() throws {
        #if os(visionOS)
        throw XCTSkip("Skipping on visionOS: springboard interaction is unreliable on the simulator.")
        #endif

        let app = XCUIApplication()
        app.launchArguments = ["--lifecycleTests"]
        let moduleRunning = app.staticTexts["Module is running."]
        XCTAssertTrue(app.launchAndWait())
        XCTAssertTrue(moduleRunning.waitForExistence(timeout: 15.0))

        let springboard = XCUIApplication(bundleIdentifier: XCUIApplication.homeScreenBundle)
        springboard.activate()

        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 15.0))

        app.activate()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15.0))
        XCTAssertTrue(moduleRunning.waitForExistence(timeout: 15.0))

        springboard.activate()
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 15.0))

        XCTAssertTrue(app.launchAndWait())
        XCTAssertTrue(moduleRunning.waitForExistence(timeout: 15.0))
    }
}
