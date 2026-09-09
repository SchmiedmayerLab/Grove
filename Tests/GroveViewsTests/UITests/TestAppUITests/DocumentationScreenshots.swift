//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions

// documentation-screenshots: launch-arguments --documentation
// documentation-screenshots: copy Validation Sources/GroveValidation/GroveValidation.docc/Resources/Validation.png
// documentation-screenshots: copy NameFields Sources/GrovePersonalInfo/GrovePersonalInfo.docc/Resources/NameFields.png
// documentation-screenshots: snapshot Tests/GroveViewsTests/__Snapshots__/SnapshotTests+Controls/optionSetPicker.option-picker-inline.png OptionSetPicker
// documentation-screenshots: snapshot Tests/GroveViewsTests/__Snapshots__/SnapshotTests+Lists/listRow.iphone-regular.png ListRow
// documentation-screenshots: snapshot Tests/GroveViewsTests/__Snapshots__/SnapshotTests/descriptionGridRow.header.png DescriptionGridRow

/// Walks the view examples to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
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
        XCTAssert(app.staticTexts["Targets"].waitForExistence(timeout: 5))

        // A view state reporting an error, as the alert the modifier presents.
        app.buttons["ViewState"].tap()
        let email = app.textFields["E-Mail Address"]
        XCTAssert(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("leland@stanford.edu")
        app.dismissKeyboard()
        app.buttons["Reset Password"].tap()
        XCTAssert(app.alerts.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        capture("ViewState")
        app.alerts.buttons["OK"].tap()
        goBack(app)

        // Name fields with both names entered and the keyboard up.
        XCTAssert(app.buttons["NameFields"].waitForExistence(timeout: 5))
        app.buttons["NameFields"].tap()
        let first = app.textFields["enter your first name"]
        XCTAssert(first.waitForExistence(timeout: 5))
        first.tap()
        first.typeText("Leland")
        let last = app.textFields["enter your last name"]
        last.tap()
        last.typeText("Stanford")
        sleep(2)
        capture("NameFields")
        app.buttons["Done"].tap()
        goBack(app)

        // The same tile with its header aligned leading, center and trailing.
        XCTAssert(app.buttons["Tiles"].waitForExistence(timeout: 5))
        app.buttons["Tiles"].tap()
        XCTAssert(app.staticTexts["Evening Medication"].waitForExistence(timeout: 5))
        sleep(2)
        capture("Tiles")
        goBack(app)

        // Placeholder rows shimmering while content loads.
        XCTAssert(app.buttons["SkeletonLoading"].waitForExistence(timeout: 5))
        app.buttons["SkeletonLoading"].tap()
        sleep(2)
        capture("SkeletonLoading")
        goBack(app)

        // Every field failing its rule, with the keyboard up.
        XCTAssert(app.buttons["Validation TextField"].waitForExistence(timeout: 5))
        app.buttons["Validation TextField"].tap()
        let mail = app.textFields["Email"]
        XCTAssert(mail.waitForExistence(timeout: 5))
        mail.tap()
        mail.typeText("leland.stanford")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("secret")
        let username = app.textFields["Username"]
        username.tap()
        username.typeText("a")
        username.typeText(XCUIKeyboardKey.delete.rawValue)
        sleep(2)
        capture("Validation")
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssert(back.waitForExistence(timeout: 15))
        back.tap()
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
