//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: resources Sources/GroveSchedulerUI/GroveSchedulerUI.docc/Resources
// documentation-screenshots: launch-arguments --documentation
// documentation-screenshots: copy Schedule Sources/Grove/Grove.docc/Resources/Schedule.png

/// Walks the schedule to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
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
        sleep(1)
        app.buttons["Schedule"].tap()
        XCTAssert(app.staticTexts["Today"].waitForExistence(timeout: 10))
        sleep(2)
        hideTestControls(app)
        capture("Schedule")

        choose(app, "Alignment", "Center")
        sleep(1)
        hideTestControls(app)
        capture("ScheduleCentered")

        choose(app, "Alignment", "Leading")
        choose(app, "Date", "Tomorrow")
        sleep(1)
        hideTestControls(app)
        capture("ScheduleTomorrow")

        // The info button on a tile opens the event's details.
        let moreInformation = app.buttons.matching(identifier: "More Information").firstMatch
        XCTAssert(moreInformation.wait(for: \.isHittable, toEqual: true, timeout: 3))
        moreInformation.tap()
        XCTAssert(app.navigationBars.staticTexts["More Information"].waitForExistence(timeout: 4))
        sleep(2)
        capture("EventDetails")
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ picker: String, _ option: String) {
        XCTAssert(app.navigationBars.buttons["More"].waitForExistence(timeout: 6))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons[picker].waitForExistence(timeout: 3))
        app.buttons[picker].tap()
        XCTAssert(app.buttons[option].waitForExistence(timeout: 3))
        app.buttons[option].tap()
        sleep(1)
    }

    /// The test app's own controls sit behind its menu; the pictures show the schedule alone.
    @MainActor
    private func hideTestControls(_ app: XCUIApplication) {
        XCTAssert(app.navigationBars.buttons["More"].waitForExistence(timeout: 6))
        app.navigationBars.buttons["More"].tap()
        XCTAssert(app.buttons["Hide Content"].waitForExistence(timeout: 3))
        app.buttons["Hide Content"].tap()
        sleep(1)
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
