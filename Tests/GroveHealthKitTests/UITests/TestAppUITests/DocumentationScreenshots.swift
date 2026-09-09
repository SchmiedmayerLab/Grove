//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTHealthKit

// documentation-screenshots: launch-arguments --collectedSamplesOnly
// documentation-screenshots: resources Sources/GroveHealthKitUI/GroveHealthKitUI.docc/Resources
// documentation-screenshots: snapshot Tests/GroveHealthKitTests/__Snapshots__/GroveHealthKitUITests/multiEntryHealthChartViewSnapshot.1.png HealthChart

/// Seeds a day of samples and charts it; run through `Scripts/documentation-screenshots.sh`.
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
        let askForAuthorization = app.buttons["Ask for authorization"]
        XCTAssert(askForAuthorization.waitForExistence(timeout: 30))
        if askForAuthorization.isEnabled {
            askForAuthorization.tap()
            app.handleHealthKitAuthorization()
        }

        app.performMoreMenuAction("Add a Day of Samples")
        app.handleHealthKitAuthorization(timeout: 5)

        XCTAssert(app.buttons["Samples Query"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Samples Query"].tap()
        XCTAssert(app.navigationBars["Samples Query"].waitForExistence(timeout: 5))
        sleep(3)
        capture("HealthChart")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
