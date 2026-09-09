//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: copy Welcome Sources/Grove/Grove.docc/Resources/Onboarding.png
// documentation-screenshots: copy Welcome Sources/GroveViews/GroveViews.docc/Resources/Welcome.png
// documentation-screenshots: copy ImageHeader Sources/GroveViews/GroveViews.docc/Resources/ImageHeader.png

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
        XCTAssert(app.staticTexts["Heart Health Study"].waitForExistence(timeout: 3))
        sleep(2)
        capture("Welcome")
        app.buttons["Learn More"].tap()
        XCTAssert(app.staticTexts["What to Expect"].waitForExistence(timeout: 3))
        while !app.buttons["Continue"].exists {
            app.buttons["Next"].tap()
        }
        sleep(2)
        capture("SequentialSteps")
        app.buttons["Continue"].tap()
        XCTAssert(app.staticTexts["Health Access"].waitForExistence(timeout: 3))
        sleep(2)
        capture("ImageHeader")
        app.buttons["Grant Access"].tap()
        XCTAssert(app.staticTexts["Study Details"].waitForExistence(timeout: 3))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        sleep(2)
        capture("ScrolledTitle")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
