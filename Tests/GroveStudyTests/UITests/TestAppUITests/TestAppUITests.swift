//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTest
import XCTestExtensions
import XCTHealthKit


class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    

    @MainActor
    func testStudyEnrollment() throws {
        let app = XCUIApplication()
        // resetting the authorization guarantees the sheet, so warm and cold runs take the same path
        app.terminate()
        app.resetAuthorizationStatus(for: .health)
        sleep(for: .seconds(2))

        let completeWelcomeArticleButton = app.buttons["Complete Informational: Welcome to the Study!"]
        let completeInformationalArticleButton = app.buttons["Complete Informational: Article1 Title"]

        // enroll into version 1 of the study
        let enrollButton = app.buttons["Enroll in TestStudy (v1)"]
        XCTAssert(app.launchAndWait(for: enrollButton), "The app did not come up.")
        enrollButton.tap()
        app.handleHealthKitAuthorization(requireSheetToAppear: true)

        XCTAssert(app.staticTexts["TestStudy"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Study ID, 885099E4-6318-43CC-BFF1-7D7FAD1968F6"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Study Revision, 1"].waitForExistence(timeout: 1))
        let enrollmentDateText = DateFormatter.localizedString(from: .now, dateStyle: .short, timeStyle: .none)
        XCTAssert(app.staticTexts["Enrollment Date, \(enrollmentDateText)"].waitForExistence(timeout: 1))
        
        app.swipeUp()
        // the events are scheduled asynchronously, so they can trail the enrollment row by a few frames
        XCTAssert(app.staticTexts["Article1 Title"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Social Support"].waitForExistence(timeout: 1))

        XCTAssert(completeWelcomeArticleButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        completeWelcomeArticleButton.tap()
        XCTAssert(completeWelcomeArticleButton.waitForNonExistence(timeout: 5))
        XCTAssert(completeInformationalArticleButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        completeInformationalArticleButton.tap()
        XCTAssert(completeInformationalArticleButton.waitForNonExistence(timeout: 5))
        
        // update the study to a newer version.
        // going from 1 to 2 will remove the questionnaire component.
        // since the informational component remains, and has already been completed, we expect it to stay completed.
        app.swipeDown()
        let updateToRevision2Button = app.buttons["Update enrollment to study revision 2"]
        XCTAssert(updateToRevision2Button.wait(for: \.isHittable, toEqual: true, timeout: 5))
        updateToRevision2Button.tap()
        XCTAssert(app.staticTexts["Study Revision, 2"].waitForExistence(timeout: 10))
        XCTAssert(completeWelcomeArticleButton.waitForNonExistence(timeout: 1))
        XCTAssert(completeInformationalArticleButton.waitForNonExistence(timeout: 1))
        XCTAssert(app.staticTexts["Social Support"].waitForNonExistence(timeout: 1))

        // update the study to a newer version.
        // going from 2 to 3 will introduce a new, second informative article component.
        // we expect this to show up, and we still expect the first article to stay completed.
        let updateToRevision3Button = app.buttons["Update enrollment to study revision 3"]
        XCTAssert(updateToRevision3Button.wait(for: \.isHittable, toEqual: true, timeout: 5))
        updateToRevision3Button.tap()
        XCTAssert(app.staticTexts["Study Revision, 3"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Article2 Title"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Welcome to the Study!, Completed"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Article1 Title, Completed"].waitForExistence(timeout: 1))

        // unenroll and make sure that everything gets removed
        let unenrollButton = app.buttons["Unenroll from Study"]
        XCTAssert(unenrollButton.wait(for: \.isHittable, toEqual: true, timeout: 5))
        unenrollButton.tap()
        XCTAssert(app.staticTexts["No Events"].waitForExistence(timeout: 10))
        // the enrollment row is driven by a separate query than the events list, so it can clear a frame later
        XCTAssert(app.staticTexts["TestStudy"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Study ID"].exists)
        XCTAssertFalse(app.staticTexts["Study Revision"].exists)
        XCTAssertFalse(app.staticTexts["Enrollment Date"].exists)
    }
}
