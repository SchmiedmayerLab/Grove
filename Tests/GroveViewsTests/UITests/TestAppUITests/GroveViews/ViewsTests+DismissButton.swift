//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


extension ViewsTests {
    @MainActor
    func testDismissButton() {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["Dismiss Button"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Dismiss Button"].tap()

        XCTAssert(app.buttons["Show Sheet"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Show Sheet"].tap()
        XCTAssert(app.staticTexts["This is the Sheet"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Close"].tap()
        XCTAssert(app.staticTexts["This is the Sheet"].waitForNonExistence(timeout: 2))
    }
}
