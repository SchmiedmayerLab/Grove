//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class PersonalInfoViewsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
    }

    @MainActor
    func testNameFields() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GrovePersonalInfo")

        XCTAssert(app.buttons["Name Fields"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Name Fields"].tap()

        XCTAssert(app.staticTexts["First Name"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Last Name"].waitForExistence(timeout: 2))

        try app.textFields["enter your first name"].enter(value: "Leland")
        try app.textFields["enter your last name"].enter(value: "Stanford")

        XCTAssert(app.textFields["Leland"].waitForExistence(timeout: 2))
        XCTAssert(app.textFields["Stanford"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testUserProfile() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.launchAndWait())

        app.open(target: "GrovePersonalInfo")

        XCTAssert(app.buttons["User Profile"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["User Profile"].tap()

        XCTAssertTrue(app.staticTexts["PS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["person.crop.artframe"].waitForExistence(timeout: 5))
    }
}
