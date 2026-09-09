//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest
import XCTestExtensions


extension XCUIApplication {
    /// Perform password-credential based login.
    /// - Parameters:
    ///   - email: The email credential.
    ///   - password: The password credential.
    public func login(email: some StringProtocol, password: some StringProtocol) throws {
        try login(userId: email, password: password, field: "E-Mail Address")
    }
    
    /// Perform password-credential based login.
    /// - Parameters:
    ///   - username: The username credential.
    ///   - password: The password credential.
    public func login(username: some StringProtocol, password: some StringProtocol) throws {
        try login(userId: username, password: password, field: "Username")
    }


    private func login(userId: some StringProtocol, password: some StringProtocol, field: String) throws {
        XCTAssertTrue(textFields[field].exists)
        XCTAssertTrue(secureTextFields["Password"].exists)

        try textFields[field].enter(value: String(userId))
        try secureTextFields["Password"].enter(value: String(password))

        XCTAssertTrue(signInButton.waitForExistence(timeout: 0.5)) // might need time to to get enabled
        XCTAssertTrue(signInButton.isEnabled)
        signInButton.tap()
        
        dismissSavePasswordAlert(timeout: 7)
    }
}


extension XCUIApplication {
    /// The button that signs an existing user in on the account setup page.
    ///
    /// Tests reach the button through this property rather than by its title, so a change of wording or layout
    /// in the account views is fixed here once.
    public var signInButton: XCUIElement {
        buttons["Sign In"]
    }

    /// The button that submits the sign-up form.
    public var signUpButton: XCUIElement {
        buttons["Sign Up"]
    }

    /// The button on the account setup page that opens the sign-up form.
    public var createAccountLink: XCUIElement {
        buttons["Create Account"]
    }
}
