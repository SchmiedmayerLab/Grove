//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


final class ConsentRegressionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testIncompleteConsentDoesNotSubmitOrRetainPresentationHighlights() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Consent Validation"].waitForExistence(timeout: 5))
        app.buttons["Consent Validation"].tap()
        app.buttons["Open Consent"].tap()
        let message = app.staticTexts["Turn this on to continue"]
        let offMessage = app.staticTexts["Turn this off to continue"]
        let submit = app.buttons["I Consent"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
        XCTAssertFalse(offMessage.exists)
        submit.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(offMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.exists)
        app.buttons["Dismiss Consent"].tap()
        XCTAssertTrue(app.staticTexts["Submissions: 0"].waitForExistence(timeout: 5))

        // The same document is reused in a fresh presentation, without the previous attempt's highlights.
        app.buttons["Open Consent"].tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
        XCTAssertFalse(offMessage.exists)
        app.switches["ConsentForm:agree"].tap()
        app.switches["ConsentForm:excluded"].tap()
        submit.tap()
        XCTAssertTrue(app.staticTexts["Submissions: 1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFootersRemainAvailableAfterMarkdown() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Consent Footers"].waitForExistence(timeout: 5))
        app.buttons["Consent Footers"].tap()
        let markdownFooter = app.buttons["Markdown Footer"]
        let trailingMarkdownFooter = app.buttons["Trailing Markdown Footer"]
        XCTAssertTrue(markdownFooter.waitForExistence(timeout: 5))
        XCTAssertTrue(trailingMarkdownFooter.waitForExistence(timeout: 5))
        markdownFooter.tap()
        trailingMarkdownFooter.tap()
        XCTAssertTrue(app.staticTexts["Footer activations: 2"].waitForExistence(timeout: 5))
    }
}
