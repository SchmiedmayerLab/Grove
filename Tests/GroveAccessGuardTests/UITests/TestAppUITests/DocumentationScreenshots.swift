//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

/// Walks setting a passcode and entering a wrong one; run through
/// `Scripts/documentation-screenshots.sh`.
final class DocumentationScreenshots: XCTestCase {
    override func setUpWithError() throws {
        // The walk needs the app the script launched and the states it prepared; a plain test run skips it.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GROVE_DOCUMENTATION_SCREENSHOTS"] == "1",
            "Run through Scripts/documentation-screenshots.sh"
        )
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureDocumentationScreenshots() throws {
        let app = XCUIApplication()
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssert(app.buttons["Reset Access Guards"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        app.buttons["Reset Access Guards"].tap()

        app.buttons["Set Code"].tap()
        XCTAssert(app.staticTexts["Set Code"].waitForExistence(timeout: 5))
        sleep(2)
        capture("SetPasscode")
        app.secureTextFields["Passcode Field"].tap()
        app.secureTextFields["Passcode Field"].typeText("1234")
        XCTAssert(app.staticTexts["Repeat Code"].waitForExistence(timeout: 5))
        app.secureTextFields["Passcode Field"].tap()
        app.secureTextFields["Passcode Field"].typeText("1234")
        XCTAssert(app.images["Passcode set was successful"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()

        // A wrong code, so the page shows how it counts the attempts.
        XCTAssert(app.buttons["Access Guarded Fixed"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Access Guarded Fixed"].tap()
        XCTAssert(app.secureTextFields["Passcode Field"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.secureTextFields["Passcode Field"].tap()
        app.secureTextFields["Passcode Field"].typeText("1111")
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 Failed Attempt'")).firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        capture("EnterPasscode")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
