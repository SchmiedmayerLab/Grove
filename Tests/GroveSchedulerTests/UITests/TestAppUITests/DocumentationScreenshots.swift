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
        // The documentation shows the schedule alone: no tab bar, and no toolbar of the test app's own controls.
        // What those controls would set is passed to the launch instead.
        launch(app, arguments: [])
        capture("Schedule")

        launch(app, arguments: ["--alignment", "center"])
        capture("ScheduleCentered")

        launch(app, arguments: ["--alignment", "leading", "--date", "tomorrow"])
        capture("ScheduleTomorrow")

        // The info button on a tile opens the event's details.
        let moreInformation = app.buttons.matching(identifier: "More Information").firstMatch
        XCTAssert(moreInformation.wait(for: \.isHittable, toEqual: true, timeout: 3))
        moreInformation.tap()
        XCTAssert(app.navigationBars.staticTexts["More Information"].waitForExistence(timeout: 4))
        sleep(2)
        capture("EventDetails")
    }

    /// Launches the app into the state a picture needs, with the test app's own controls left out.
    @MainActor
    private func launch(_ app: XCUIApplication, arguments: [String]) {
        app.terminate()
        app.launchArguments = ["--documentation"] + arguments
        app.launch()
        XCTAssert(app.staticTexts["Schedule"].waitForExistence(timeout: 10))
        // Which tiles the day holds depends on the date; a tile with an action on it says the schedule is there.
        XCTAssert(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete'")).firstMatch.waitForExistence(timeout: 10))
        sleep(2)
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(12) // long enough for the script's two shots and their checks
    }
}
