//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
@testable import XCTestExtensions


@MainActor
final class DeleteAppTests: XCTestCase {
    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    func testDeleteAndLaunch() throws {
        #if os(macOS) || os(watchOS)
        throw XCTSkip("Not supported on this platform")
        #endif
        
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        
        XCTAssert(app.buttons["Text Entry"].waitForExistence(timeout: 5.0))
        app.buttons["Text Entry"].tap()
        XCTAssert(app.staticTexts["No text set ..."].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["No secure text set ..."].exists)
    }
    
    
    #if os(iOS)
    func testDeleteAndLaunchWithHealthKitSample() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Not supported on this platform")
        }
        
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        
        XCTAssert(app.buttons["HealthKitDataEntry"].waitForExistence(timeout: 5.0))
        app.buttons["HealthKitDataEntry"].tap()
        
        XCTAssert(app.buttons["Add a HealthKit sample"].waitForExistence(timeout: 3))
        app.buttons["Add a HealthKit sample"].tap()
        
        if app.staticTexts["Has access"].waitForNonExistence(timeout: 2) {
            // if the view isn't telling us that it has access, it's currently requesting access
            app.tables.staticTexts["Turn On All"].tap()
            app.buttons["UIA.Health.Allow.Button"].tap()
        }
        
        XCTAssert(app.staticTexts["Did add sample!"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Did add sample!"].exists)
        
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
    }
    #endif
    
    
    @available(macOS, unavailable)
    @available(watchOS, unavailable)
    func testDeleteAndLaunchFromFirstPage() throws {
        #if os(macOS) || os(watchOS)
        throw XCTSkip("Not supported on this platform")
        #endif
        #if os(visionOS)
        // currently don't know how to swipe on the Reality Launcher. So not a super big use case for us now.
        throw XCTSkip("VisionOS will typically have apps installed on the first screen anyways.")
        #endif
        let springboard = XCUIApplication(bundleIdentifier: XCUIApplication.homeScreenBundle)
        springboard.activate()
        springboard.swipeRight()
        
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        
        XCTAssert(app.buttons["Text Entry"].waitForExistence(timeout: 5.0))
        app.buttons["Text Entry"].tap()

        XCTAssert(app.staticTexts["No text set ..."].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["No secure text set ..."].exists)
    }
}
