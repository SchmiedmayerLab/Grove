//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: copy SignedConsent Sources/Grove/Grove.docc/Resources/Consent.png

/// Walks the screenshot flow to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
final class DocumentationScreenshots: XCTestCase {
    override func setUpWithError() throws {
        // The walk needs the app the script launched and the states it prepared; a plain test run skips it.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GROVE_DOCUMENTATION_SCREENSHOTS"] == "1",
            "Run through Scripts/documentation-screenshots.sh"
        )
        continueAfterFailure = false
    }

    func testCaptureDocumentationScreenshots() throws {
        let app = XCUIApplication()
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssert(app.buttons["Screenshots"].waitForExistence(timeout: 10))
        app.buttons["Screenshots"].tap()
        XCTAssert(app.staticTexts["Study Consent"].waitForExistence(timeout: 3))
        // A form read to its end and signed: the signature sits above the action, the text scrolled away.
        scrollToEnd(app)
        sign(app)
        sleep(2)
        capture("SignedConsent")
        app.buttons["I Consent"].tap()
        XCTAssert(app.switches.firstMatch.waitForExistence(timeout: 3))
        app.switches.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'No selection'")).firstMatch.tap()
        XCTAssert(app.buttons["Sometimes"].waitForExistence(timeout: 2))
        app.buttons["Sometimes"].tap()
        sign(app)
        sleep(2)
        capture("InteractiveElements")
        app.buttons["I Consent"].tap()
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'To take part'")).firstMatch.waitForExistence(timeout: 3))
        sign(app)
        sleep(2)
        capture("RequiredSelection")
        // The required choice is still "No", so continuing marks it instead of moving on.
        app.buttons["I Consent"].tap()
        sleep(2)
        capture("IncompleteForm")
    }

    /// Drags the upper part of the page, where only text scrolls, so the canvas never takes the gesture as ink.
    private func scrollToEnd(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
    }

    private func sign(_ app: XCUIApplication) {
        XCTAssert(app.scrollViews["Signature Field"].waitForExistence(timeout: 3))
        app.scrollViews["Signature Field"].swipeRight()
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
