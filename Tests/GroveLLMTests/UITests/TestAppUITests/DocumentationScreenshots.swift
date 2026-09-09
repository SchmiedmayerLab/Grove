//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest

// documentation-screenshots: launch-arguments --resetSecureStorage
// documentation-screenshots: resources Sources/GroveLLMOpenAI/GroveLLMOpenAI.docc/Resources

/// Walks the OpenAI onboarding to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
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
        XCTAssert(app.buttons["LLMOpenAI"].waitForExistence(timeout: 10))
        app.buttons["LLMOpenAI"].tap()
        XCTAssert(app.buttons["Onboarding"].waitForExistence(timeout: 5))
        app.buttons["Onboarding"].tap()
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'API Key'")).firstMatch
        XCTAssert(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssert(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("sk-…")
        sleep(1)
        capture("APITokenStep")
        let next = app.buttons.matching(NSPredicate(format: "label IN {'Next', 'Continue'}")).firstMatch
        XCTAssert(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssert(app.descendants(matching: .any).matching(identifier: "modelPicker").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        capture("ModelStep")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
