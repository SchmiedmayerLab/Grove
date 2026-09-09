//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveAccount

// documentation-screenshots: launch-arguments --service-type withIdentityProvider --credentials create
// documentation-screenshots: copy AccountSetup Sources/Grove/Grove.docc/Resources/AccountSetup.png

/// Walks the account setup, sign-up, an incomplete sign-up, the password reset, the overview with its detail pages, the edit form, and then
/// the setup page of a signed-in account and the sheet that finishes an incomplete one; run through `Scripts/documentation-screenshots.sh`.
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
        XCTAssertTrue(app.staticTexts["Grove Account"].waitForExistence(timeout: 10))

        app.openAccountSetup(timeout: 5)
        sleep(2)
        capture("AccountSetup")

        app.openSignup()
        sleep(2)
        capture("SignUp")

        app.signUpButton.tap()
        sleep(1)
        app.dismissKeyboard()
        sleep(1)
        capture("IncompleteSignUp")

        try app.closeSignupForm()
        XCTAssertTrue(app.staticTexts["Your Account"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.buttons["Forgot Password?"].waitForExistence(timeout: 3))
        app.buttons["Forgot Password?"].tap()
        XCTAssertTrue(app.buttons["Reset Password"].waitForExistence(timeout: 3))
        sleep(2)
        capture("ResetPassword")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Your Account"].waitForExistence(timeout: 3))

        try app.login(email: Defaults.email, password: Defaults.password)
        if app.buttons["Finish"].waitForExistence(timeout: 3) {
            app.buttons["Finish"].tap()
        }
        XCTAssertTrue(app.staticTexts[Defaults.email].waitForExistence(timeout: 10))

        app.openAccountOverview(timeout: 5)
        sleep(2)
        capture("AccountOverview")

        XCTAssertTrue(app.buttons["Name, E-Mail Address"].waitForExistence(timeout: 3))
        app.buttons["Name, E-Mail Address"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 3))
        sleep(2)
        capture("AccountDetails")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["Sign-In & Security"].waitForExistence(timeout: 3))
        app.buttons["Sign-In & Security"].tap()
        XCTAssertTrue(app.buttons["Change Password"].waitForExistence(timeout: 3))
        app.buttons["Change Password"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Change Password"].waitForExistence(timeout: 3))
        try app.secureTextFields["New Password"].enter(value: "correct-horse-battery", options: .disableKeyboardDismiss)
        try app.secureTextFields["Repeat Password"].enter(value: "correct-horse", options: .disableKeyboardDismiss)
        app.dismissKeyboard()
        sleep(1)
        capture("ChangePassword")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Sign-In & Security"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        sleep(2)
        capture("AccountEdit")

        // The last two states need the app launched into them.
        app.launch(serviceType: .withIdentityProvider, credentials: .createAndSignIn)
        XCTAssertTrue(app.staticTexts["Grove Account"].waitForExistence(timeout: 10))
        app.openAccountSetup(timeout: 5)
        XCTAssertTrue(app.buttons["Logout"].waitForExistence(timeout: 3))
        sleep(2)
        capture("SignedIn")

        app.launch(config: .allRequiredWithBio, credentials: .createAndSignIn)
        XCTAssertTrue(app.staticTexts["Finish Account Setup"].waitForExistence(timeout: 10))
        sleep(2)
        capture("FinishSetup")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
