//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


extension ViewsTests {
    @MainActor
    func testPageActionsHoldOneButtonBack() throws {
        #if os(macOS)
        throw XCTSkip("The segmented picker exposes radio buttons on macOS")
        #endif
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["Page Actions"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Page Actions"].tap()

        let waiting = app.buttons["Waiting"]
        let skip = app.buttons["Skip"]
        XCTAssert(waiting.waitForExistence(timeout: 2))
        XCTAssertFalse(waiting.isEnabled)
        XCTAssertTrue(skip.isEnabled)

        app.buttons["Secondary"].tap()
        XCTAssert(waiting.wait(for: \.isEnabled, toEqual: true, timeout: 2))
        XCTAssertFalse(skip.isEnabled)

        app.buttons["None"].tap()
        XCTAssert(skip.wait(for: \.isEnabled, toEqual: true, timeout: 2))
        XCTAssertTrue(waiting.isEnabled)
    }
}
