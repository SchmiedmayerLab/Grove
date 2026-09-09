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
        // The package sits further down the list; scroll until its row is on screen.
        let package = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'swift-collections'")).firstMatch
        for _ in 0..<8 where !package.exists {
            app.swipeUp()
        }
        XCTAssert(package.waitForExistence(timeout: 5))
        package.tap()
        sleep(2)
        capture("PackageLicense")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
