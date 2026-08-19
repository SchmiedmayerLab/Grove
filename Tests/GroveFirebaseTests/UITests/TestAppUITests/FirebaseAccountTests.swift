//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveAccount


/// The `FirebaseAccountTests` require the Firebase Authentication Emulator to run at port 9099.
///
/// Refer to https://firebase.google.com/docs/emulator-suite/connect_auth about more information about the
/// Firebase Local Emulator Suite.
final class FirebaseAccountTests: XCTestCase { // swiftlint:disable:this type_body_length
    override func setUp() async throws {
        continueAfterFailure = false

        try await FirebaseClient.deleteAllAccounts()
        try await FirebaseClient.waitForAccounts([])
    }

    @MainActor
    func testAccountSignUp() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssert(accounts.isEmpty)

        try app.signup(username: "test@username1.edu", password: "TestPassword1", givenName: "Test1", familyName: "Username1")

        XCTAssert(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Logout"].tap()

        try app.signup(username: "test@username2.edu", password: "TestPassword2", givenName: "Test2", familyName: "Username2")

        try await FirebaseClient.waitForAccounts(
            [
                FirestoreAccount(email: "test@username1.edu", displayName: "Test1 Username1"),
                FirestoreAccount(email: "test@username2.edu", displayName: "Test2 Username2")
            ]
        )

        XCTAssert(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Logout"].tap()
    }

    
    @MainActor
    func testAccountLogin() async throws {
        try await FirebaseClient.createAccount(email: "test@username1.edu", password: "TestPassword1", displayName: "Test1 Username1")
        try await FirebaseClient.createAccount(email: "test@username2.edu", password: "TestPassword2", displayName: "Test2 Username2")
        
        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(
            accounts.sorted(by: { $0.email < $1.email }),
            [
                FirestoreAccount(email: "test@username1.edu", displayName: "Test1 Username1"),
                FirestoreAccount(email: "test@username2.edu", displayName: "Test2 Username2")
            ]
        )
        
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username1.edu", password: "TestPassword1")
        XCTAssert(app.staticTexts["test@username1.edu"].waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Logout"].tap()

        try app.login(username: "test@username2.edu", password: "TestPassword2")
        XCTAssert(app.staticTexts["test@username2.edu"].waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Logout"].tap()
    }

    @MainActor
    func testAccountLogout() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        XCTAssert(app.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        let logoutButtons = app.buttons.matching(identifier: "Logout").allElementsBoundByIndex
        XCTAssert(!logoutButtons.isEmpty)
        let logout = logoutButtons.last! // swiftlint:disable:this force_unwrapping
        XCTAssert(logout.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        logout.tap()

        let alert = "Are you sure you want to logout?"
        XCTAssertTrue(app.alerts[alert].waitForExistence(timeout: 6.0))
        let confirm = app.alerts[alert].scrollViews.otherElements.buttons["Logout"]
        XCTAssertTrue(confirm.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        confirm.tap()

        // The account survives a logout, so we wait for the app to drop the account before we check the emulator.
        XCTAssertTrue(app.buttons["Logout"].waitForNonExistence(timeout: 10.0))

        let accounts2 = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(
            accounts2.sorted(by: { $0.email < $1.email }),
            [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")]
        )
    }

    @MainActor
    func testAccountRemoval() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        XCTAssert(app.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        XCTAssertTrue(app.buttons["Edit"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Edit"].tap()
        if !app.buttons["Delete Account"].waitForExistence(timeout: 4.0), app.buttons["Edit"].isHittable {
            // The overview is still settling while it loads the account details, which can swallow the first tap.
            app.buttons["Edit"].tap()
        }

        XCTAssertTrue(app.buttons["Delete Account"].wait(for: \.isHittable, toEqual: true, timeout: 4.0))
        app.buttons["Delete Account"].tap()

        let alert = "Are you sure you want to delete your account?"
        XCTAssertTrue(app.alerts[alert].waitForExistence(timeout: 6.0))
        let delete = app.alerts[alert].scrollViews.otherElements.buttons["Delete"]
        XCTAssertTrue(delete.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        delete.tap()

        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        try await FirebaseClient.waitForAccounts([])
    }

    @MainActor
    func testAccountEdit() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        XCTAssertTrue(app.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        XCTAssertTrue(app.buttons["Name, E-Mail Address"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Name, E-Mail Address"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 10.0))

        // CHANGE NAME
        XCTAssertTrue(app.buttons["Name, Username Test"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Name, Username Test"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name"].waitForExistence(timeout: 10.0))

        try app.textFields["enter last name"].delete(count: 4, options: .disableKeyboardDismiss)
        try app.textFields["enter last name"].enter(value: "Test1", options: .skipTextFieldSelection)

        XCTAssertTrue(app.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 10.0))
        XCTAssertTrue(app.staticTexts["Name, Username Test1"].waitForExistence(timeout: 5.0))

        // CHANGE EMAIL ADDRESS
        XCTAssertTrue(app.buttons["E-Mail Address, test@username.edu"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["E-Mail Address, test@username.edu"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["E-Mail Address"].waitForExistence(timeout: 10.0))

        try app.textFields["E-Mail Address"].delete(count: 3, options: .disableKeyboardDismiss)
        try app.textFields["E-Mail Address"].enter(value: "de", options: .skipTextFieldSelection)

        XCTAssertTrue(app.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 4.0))
        XCTAssertTrue(app.staticTexts["E-Mail Address, test@username.de"].waitForExistence(timeout: 5.0))


        let newAccounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(newAccounts, [FirestoreAccount(email: "test@username.de", displayName: "Username Test1")])
    }

    @MainActor
    private func passwordChangeBase() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Sign-In & Security"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Sign-In & Security"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Sign-In & Security"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Change Password"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Change Password"].tap()


        XCTAssertTrue(app.navigationBars.staticTexts["Change Password"].waitForExistence(timeout: 2.0))

        try app.secureTextFields["enter password"].enter(value: "1234567890")
        try app.secureTextFields["re-enter password"].enter(value: "1234567890")

        XCTAssertTrue(app.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Done"].tap()
    }

    @MainActor
    func testPasswordChange() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()

        
        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        XCTAssertTrue(app.navigationBars.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Account Overview"].tap() // back button

        XCTAssertTrue(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Logout"].tap() // we tap the custom button to be lest dependent on the other tests and not deal with the alert

        try app.login(username: "test@username.edu", password: "1234567890", close: false)
        XCTAssertTrue(app.staticTexts["Username Test"].waitForExistence(timeout: 6.0))
    }

    @MainActor
    func testPasswordChangeWrong() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()


        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("Wrong!") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()


        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testPasswordChangeCancel() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()


        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Cancel"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.alerts["Authentication Required"].buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Change Password"].exists) // ensure we stay in the sheet
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Account Overview"].tap() // back button

        XCTAssertTrue(app.navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Logout"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Logout"].tap() // we tap the custom button to be lest dependent on the other tests and not deal with the alert

        try app.login(username: "test@username.edu", password: "TestPassword", close: false) // login with previous password!
        XCTAssertTrue(app.staticTexts["Username Test"].waitForExistence(timeout: 6.0))
    }

    @MainActor
    func testPasswordReset() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        XCTAssertTrue(app.buttons["Account Setup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Setup"].tap()

        XCTAssertTrue(app.buttons["Forgot Password?"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Forgot Password?"].tap()

        XCTAssertTrue(app.buttons["Reset Password"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))

        let fields = app.textFields.matching(identifier: "E-Mail Address").allElementsBoundByIndex
        try fields.last?.enter(value: "non-existent@username.edu")

        XCTAssertTrue(app.buttons["Reset Password"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Reset Password"].tap()

        XCTAssertTrue(app.staticTexts["Sent out a link to reset the password."].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.buttons["Done"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Done"].tap()
    }

    @MainActor
    func testInvalidCredentials() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "unknown@example.de", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.alerts["Invalid Credentials"].scrollViews.buttons["OK"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.alerts["Invalid Credentials"].scrollViews.buttons["OK"].tap()

        XCTAssertTrue(app.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        app.buttons["Close"].tap()
        app.dismissSavePasswordAlert(timeout: 7) // sometimes shows up even though there was no successful login

        XCTAssertTrue(app.buttons["Account Setup"].waitForExistence(timeout: 2.0))

        // signing in with unknown credentials or credentials with a incorrect password are two different errors
        // that should, nonetheless, be treated equally in UI.
        try app.login(username: "test@username.edu", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 6.0))
        let okButton = app.alerts["Invalid Credentials"].scrollViews.otherElements.buttons["OK"]
        XCTAssertTrue(okButton.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        okButton.tap()
    }

    @MainActor
    func testBasicSignInWithApple() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        XCTAssertTrue(app.buttons["Account Setup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Setup"].tap()

        XCTAssertTrue(app.buttons["Sign in with Apple"].wait(for: \.isHittable, toEqual: true, timeout: 10.0))
        app.buttons["Sign in with Apple"].tap()

        // The Apple ID sheet is hosted out of process; XCTest surfaces it to an interruption monitor only once an
        // interaction is found blocked, so we wait on the sheet directly instead of poking the app to provoke it.
        let authSheet = XCUIApplication(bundleIdentifier: "com.apple.AuthKitUIService")
        let close = authSheet.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}")).firstMatch
        if close.waitForExistence(timeout: 15.0) {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10.0))
        } else {
            XCTAssertEqual(app.state, .runningForeground)
        }

        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 10.0))
    }

    @MainActor
    func testSignupAccountLinking() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--account-storage"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        XCTAssertTrue(app.buttons["Account Setup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Setup"].tap()

        XCTAssertTrue(app.buttons["Anonymous Signup"].wait(for: \.isHittable, toEqual: true, timeout: 4.0))
        app.buttons["Anonymous Signup"].tap()

        XCTAssertTrue(app.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Close"].tap()

        XCTAssertTrue(app.staticTexts["User, Anonymous"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["New User, Yes"].exists)
        XCTAssertTrue(app.staticTexts["Account Id, Stable"].exists)

        try app.signup(username: "test@username2.edu", password: "TestPassword2", givenName: "Leland", familyName: "Stanford", biography: "Bio")

        XCTAssertTrue(app.staticTexts["test@username2.edu"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.staticTexts["New User, Yes"].exists) // ensure new user flag persists
        XCTAssertTrue(app.staticTexts["Account Id, Stable"].exists) // ensure we actually linked the account and not accidentally created a new one

        XCTAssertTrue(app.buttons["Account Overview"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        app.buttons["Account Overview"].tap()
        XCTAssert(app.staticTexts["Leland Stanford"].waitForExistence(timeout: 2.0))
        // The biography lives in the external account storage and arrives after the rest of the details.
        XCTAssert(app.staticTexts["Biography, Bio"].waitForExistence(timeout: 5.0))
    }

    @MainActor
    func testAccountReadyUponStartup() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up.")

        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 2.0))

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10.0))

        XCTAssert(app.launchAndWait(for: app.buttons["FirebaseAccount"]), "The app did not come up again.")

        app.buttons["FirebaseAccount"].tap()

        XCTAssert(app.staticTexts["User Present on Startup, Yes"].waitForExistence(timeout: 5.0))
        XCTAssertFalse(app.staticTexts["User Present on Startup, No"].exists)
    }
}


extension XCUIApplication {
    func login(username: String, password: String, close: Bool = true) throws {
        XCTAssertTrue(buttons["Account Setup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        buttons["Account Setup"].tap()
        XCTAssertTrue(self.buttons["Login"].waitForExistence(timeout: 2.0))

        try login(email: username, password: password)

        if close {
            XCTAssertTrue(staticTexts[username].waitForExistence(timeout: 5.0))
            XCTAssertTrue(self.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
            self.buttons["Close"].tap()
        }
    }

    func signup(username: String, password: String, givenName: String, familyName: String, biography: String? = nil) throws {
        XCTAssertTrue(buttons["Account Setup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        buttons["Account Setup"].tap()
        XCTAssertTrue(buttons["Signup"].wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        buttons["Signup"].tap()

        XCTAssertTrue(staticTexts["Please fill out the details below to create your new account."].waitForExistence(timeout: 6.0))

        try collectionViews.textFields["E-Mail Address"].enter(value: username)
        try collectionViews.secureTextFields["Password"].enter(value: password)
        
        try textFields["enter first name"].enter(value: givenName)
        try textFields["enter last name"].enter(value: familyName)

        if let biography {
            try textFields["Biography"].enter(value: biography)
        }

        XCTAssertTrue(collectionViews.buttons["Signup"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        collectionViews.buttons["Signup"].tap()
        dismissSavePasswordAlert(timeout: 7)

        XCTAssertTrue(staticTexts["Create a new Account"].waitForNonExistence(timeout: 10.0))
        XCTAssertTrue(staticTexts["Your Account"].waitForExistence(timeout: 10.0))
        XCTAssertTrue(navigationBars.buttons["Close"].wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        navigationBars.buttons["Close"].tap()
    }
}


// swiftlint:disable:this file_length
