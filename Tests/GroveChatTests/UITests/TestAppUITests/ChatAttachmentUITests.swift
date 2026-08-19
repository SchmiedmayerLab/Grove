//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers the two places a message points at something outside itself: an attached file, and the sources behind an
/// answer.
///
/// Neither system picker is driven here. The test app seeds a message that already carries a file and an answer that
/// already carries citations, which is the state the pickers leave behind anyway — so what is under test is the
/// chat's own rendering rather than the reliability of `UIDocumentPickerViewController`. Quick Look and the sources
/// sheet are both presented for real, so the parts that only exist once presented are still exercised.
@MainActor
final class ChatAttachmentUITests: XCTestCase {
    override func setUp() async throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
        XCTAssert(app.launchAndWait(for: app.textFields["Message Input Textfield"]), "The chat did not come up after launch.")
    }

    func testAnAttachedFileIsNamedAndSized() throws {
        let app = XCUIApplication()
        try send("attach this", in: app)

        // Name and size are one element to VoiceOver: two labels for one chip would be read as two controls.
        let chip = app.buttons["fixture.txt, 60 bytes"]
        XCTAssert(chip.waitForExistence(timeout: 10), "The file should be named and sized on its chip.")
        XCTAssert(chip.isHittable, "The chip has to be reachable to open the file.")
    }

    func testTappingAnAttachedFileOpensTheSystemPreview() throws {
        let app = XCUIApplication()
        try send("attach this", in: app)

        let chip = app.buttons["fixture.txt, 60 bytes"]
        XCTAssert(chip.waitForExistence(timeout: 10))
        chip.tap()

        // Quick Look titles itself with the file's base name, which is the cheapest proof it is the presenter rather
        // than something the chat drew itself. What that bar then offers is Apple's to decide and varies by device,
        // so nothing here asserts on its contents — only that the file reached it and can be dismissed again.
        let preview = app.navigationBars["fixture"]
        XCTAssert(preview.waitForExistence(timeout: 10), "Tapping the chip should hand the file to Quick Look.")

        let dismissal = preview.buttons.matching(
            NSPredicate(format: "label IN {'close', 'Close', 'Done', 'Cancel'}")
        ).firstMatch
        XCTAssert(dismissal.waitForExistence(timeout: 5), "The preview should offer a way out.")
        dismissal.tap()
        XCTAssert(preview.waitForNonExistence(timeout: 10), "Closing the preview should come back to the chat.")
        XCTAssert(chip.exists, "The message keeps its attachment after a preview.")
    }

    func testAnAnsweredQuestionSummarisesItsSources() throws {
        let app = XCUIApplication()
        try send("sources please", in: app)

        // Two sources are named and the rest becomes a count, so the line stays one line.
        XCTAssert(
            app.staticTexts["en.wikipedia.org, uit.stanford.edu +1"].waitForExistence(timeout: 10),
            "The footer should name the first sources and count the rest."
        )
        XCTAssert(
            app.buttons["3 sources"].exists,
            "The summary reads as a count to VoiceOver rather than as the truncated list."
        )
    }

    func testTheSourcesSheetGroupsWebAndFileSources() throws {
        let app = XCUIApplication()
        try send("sources please", in: app)

        let summary = app.buttons["3 sources"]
        XCTAssert(summary.waitForExistence(timeout: 10))
        summary.tap()

        let sheet = app.navigationBars["Sources"]
        XCTAssert(sheet.waitForExistence(timeout: 5), "Tapping the summary should open the full list.")
        XCTAssert(app.staticTexts["Files · 1"].exists, "Files should be grouped and counted.")
        XCTAssert(app.staticTexts["Web · 2"].exists, "Web pages should be grouped and counted.")

        // A web source carries its title and its host, and can be opened.
        XCTAssert(app.buttons["Reykjavík — Wikipedia, en.wikipedia.org"].exists)
        XCTAssert(app.buttons["Iceland | University IT, uit.stanford.edu"].exists)

        // A file has nowhere to open, so it is listed rather than offered as a button, and it is not repeated under
        // itself when its title already is its file name.
        XCTAssert(app.staticTexts["atlas.pdf"].exists)
        XCTAssertFalse(app.buttons["atlas.pdf"].exists, "A file source should not read as a link.")
        XCTAssertFalse(app.staticTexts["atlas.pdf, atlas.pdf"].exists, "A file should not be listed under itself.")

        sheet.buttons["Close"].tap()
        XCTAssert(sheet.waitForNonExistence(timeout: 5), "Closing should put the list away.")
        XCTAssert(summary.exists, "The answer keeps its sources after the list closes.")
    }

    private func send(_ message: String, in app: XCUIApplication) throws {
        let composer = app.textFields["Message Input Textfield"]
        XCTAssert(composer.wait(for: \.isHittable, toEqual: true, timeout: 5))
        try composer.enter(value: message, options: [.disableKeyboardDismiss])
        let send = app.buttons["Send Message"]
        XCTAssert(send.wait(for: \.isHittable, toEqual: true, timeout: 5))
        send.tap()
    }
}
