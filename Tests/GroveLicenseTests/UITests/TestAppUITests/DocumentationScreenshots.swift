//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

/// Shows the package list and one package's license; run through `Scripts/documentation-screenshots.sh`.
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
        XCTAssert(app.buttons["TestApp, MIT, Version: 1.0"].waitForExistence(timeout: 15))
        sleep(2)
        capture("ContributionsList")
        // Grove's own row, whose MIT license reads as a license rather than as a wall of clauses.
        XCTAssert(app.staticTexts["License Information"].waitForExistence(timeout: 5))
        let package = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'TestApp'")).firstMatch
        XCTAssert(package.waitForExistence(timeout: 10))
        package.tap()
        // The license page is one long text, and every query against it has to read the whole thing and times
        // out; the walk waits for the page rather than asking about it.
        sleep(4)
        capture("PackageLicense")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(12) // long enough for the script's two shots and their checks
    }
}
