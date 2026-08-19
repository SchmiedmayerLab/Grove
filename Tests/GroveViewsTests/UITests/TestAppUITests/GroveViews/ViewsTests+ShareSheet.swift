//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


extension ViewsTests {
    @MainActor
    func testShareSheet() {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GroveViews", waitingFor: app.buttons["Geometry Reader"])

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        XCTAssert(app.buttons["Share Sheet"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Share Sheet"].tap()

        /// Triggers one of the share buttons, checks the presented share sheet's header, and closes it again.
        func share(_ buttonTitle: String, expecting expected: XCUIApplication.ExpectedShareSheetHeader, line: UInt = #line) {
            let button = app.buttons[buttonTitle]
            XCTAssert(button.wait(for: \.isHittable, toEqual: true, timeout: 5), line: line)
            button.tap()
            app.assertShareSheetHeader(expected, line: line)
            let closeButton = app.buttons["header.closeButton"]
            XCTAssert(closeButton.wait(for: \.isHittable, toEqual: true, timeout: 5), line: line)
            closeButton.tap()
            XCTAssert(app.otherElements["ShareSheet.RemoteContainerView"].waitForNonExistence(timeout: 5), line: line)
        }

        share("Share Text", expecting: .init(title: "Hello Grove!", filetype: nil))
        share("Share TIFF UIImage via URL", expecting: .init(title: "jellybeans_USC-SIPI", filetype: "TIFF Image"))
        share("Share PNG UIImage via URL", expecting: .init(title: "PM5544", filetype: "PNG Image"))

        app.collectionViews.firstMatch.swipeUp() // out of the window on visionOS and iPadOS

        share("Share PDF", expecting: .init(title: "grove my beloved", filetype: "PDF Document"))
        share("Share PDF via URL", expecting: .init(title: "grove my beloved", filetype: "PDF Document"))
        share("Share 2 PDFs", expecting: .init(title: "2 Documents"))
    }
}


extension XCUIApplication {
    struct ExpectedShareSheetHeader {
        /// The expected subject/title of the share sheet. when sharing a file, this typically is either the filename, or the "title" of the file (eg: something for PDFs).
        let title: String
        /// The expected filetype, if applicable.
        ///
        /// This is in the second line of the share sheet's title, and typically takes a format like `PNG Image · 23 KB`.
        /// Since the file size isn't guaranteed to be the same across different platforms and environments, we don't check for that and instead only look for the file type.
        let filetype: String?
        
        init(title: String, filetype: String? = nil) {
            self.title = title
            self.filetype = filetype
        }
    }
    
    func assertShareSheetHeader(_ expected: ExpectedShareSheetHeader, file: StaticString = #filePath, line: UInt = #line) {
        let shareSheet = otherElements["ShareSheet.RemoteContainerView"]
        XCTAssert(shareSheet.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssert(
            staticTexts[expected.title].waitForExistence(timeout: 10) || otherElements[expected.title].waitForExistence(timeout: 10),
            "Unable to find share sheet title '\(expected.title)'",
            file: file,
            line: line
        )
        if let filetype = expected.filetype {
            let predicate = NSPredicate(format: "label BEGINSWITH %@", filetype + " · ")
            XCTAssert(
                // swiftlint:disable:next line_length
                staticTexts.matching(predicate).element.waitForExistence(timeout: 10) || otherElements.matching(predicate).element.waitForExistence(timeout: 10),
                "Unable to find share sheet filetype '\(filetype)'",
                file: file,
                line: line
            )
        }
    }
}
