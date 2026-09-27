//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest


extension XCUIApplication {
    /// Close the signup form.
    /// - Parameter discardChangesIfAsked: Confirms to discard all changes if attempting to close the signup form while data was already entered.
    public func closeSignupForm(discardChangesIfAsked: Bool = true) throws {
        XCTAssertTrue(navigationBars.buttons["Close"].exists)
        try XCTUnwrap(navigationBars.buttons.matching(identifier: "Close").allElementsBoundByIndex.last).tap()

        if discardChangesIfAsked && staticTexts["Are you sure you want to discard your input?"].waitForExistence(timeout: 2.0) {
            XCTAssertTrue(buttons["Discard Input"].waitForExistence(timeout: 2.0))
            buttons["Discard Input"].tap()
        }
    }
    
    /// Fill out the signup form.
    /// - Parameters:
    ///   - email: The email address to use.
    ///   - password: The password to use.
    ///   - name: Optional name.
    ///   - genderIdentity: Optional gender identity.
    ///   - supplyDateOfBirth: Optional, specify a date of birth. If `true` this makes sure a date of birth is specified. Typically it will select the first day of the previous month.
    public func fillSignupForm(
        email: String,
        password: String,
        name: PersonNameComponents? = nil,
        genderIdentity: String? = nil,
        supplyDateOfBirth: Bool = false
    ) throws {
        // The setup page behind the sheet has fields of the same names, so everything is looked up inside the form.
        XCTAssertTrue(signupForm.textFields["E-Mail Address"].exists, "Couldn't locate E-Mail Address field")
        try signupForm.textFields["E-Mail Address"].enter(value: email)

        XCTAssertTrue(signupForm.secureTextFields["Password"].exists, "Couldn't locate Password field")
        try signupForm.secureTextFields["Password"].enter(value: password)

        if let name {
            if let firstname = name.givenName {
                try firstNameField.enter(value: firstname)
            }
            if let lastname = name.familyName {
                try lastNameField.enter(value: lastname)
            }

#if os(visionOS)
            if genderIdentity != nil || supplyDateOfBirth {
                scrollUpInSignupForm()
            }
#endif
        }

        if let genderIdentity {
            XCTAssertTrue(staticTexts["Choose not to answer"].waitForExistence(timeout: 2.0), "Didn't find Gender Identity Picker")
            self.updateGenderIdentity(from: "Choose not to answer", to: genderIdentity)
        }

        if supplyDateOfBirth {
            self.changeDateOfBirth()
        }
    }
}


extension XCUIApplication {
#if os(visionOS)
    /// Scrolls up in the  `SignupForm` on visionOS platforms.
    public func scrollUpInSignupForm() {
        // swipeUp doesn't work on visionOS, so we improvise

        if staticTexts["Name"].waitForExistence(timeout: 2.0) {
            XCTAssertTrue(staticTexts["Create a New Account"].exists)
            staticTexts["Name"].press(forDuration: 0, thenDragTo: staticTexts["Create a New Account"].firstMatch)
        } else if staticTexts["Personal Details"].exists {
            XCTAssertTrue(staticTexts["Create a New Account"].exists)
            staticTexts["Personal Details"].press(forDuration: 0, thenDragTo: staticTexts["Create a New Account"].firstMatch)
        } else {
            XCTFail("Could not scroll on visionOS")
        }
    }
#endif
}


extension XCUIApplication {
    /// Dismisses an iOS "Save Password?" alert, if one appears within `timeout` seconds.
    public func dismissSavePasswordAlert(timeout: TimeInterval) {
        let title = "Save Password?"
        #if os(visionOS)
        let alert = alerts[title]
        #else
        let alert = sheets[title] // fun fact it's actually a sheet even though it looks like an alert.
        #endif
        func imp(alert: XCUIElement) {
            let button = alert.buttons["Not Now"]
            XCTAssert(button.waitForExistence(timeout: 2))
            if button.isHittable {
                button.tap()
            } else {
                button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
        if alert.waitForExistence(timeout: timeout) {
            imp(alert: alert)
            #if os(visionOS)
            sleep(1)
            if alert.waitForExistence(timeout: timeout) {
                let realityChrome = XCUIApplication(bundleIdentifier: "com.apple.RealityChrome")
                realityChrome.buttons["CloseButton"].tap()
                sleep(1)
                self.activate()
                sleep(1)
                imp(alert: alert)
                sleep(1)
            }
            #endif
        }
    }
}


extension XCUIApplication {
    /// The first-name field of the sign-up form and the name editors.
    public var firstNameField: XCUIElement {
        textFields["First Name"]
    }

    /// The last-name field of the sign-up form and the name editors.
    public var lastNameField: XCUIElement {
        textFields["Last Name"]
    }
}


extension XCUIApplication {
    /// The sign-up form's contents, distinct from the setup page that stays behind its sheet.
    public var signupForm: XCUIElement {
        otherElements["Sign-Up Form"]
    }
}
