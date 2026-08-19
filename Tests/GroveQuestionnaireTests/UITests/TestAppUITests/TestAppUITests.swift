//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions

/*
 IDEAS:
 - test that when you select an MC option w/ follow up questions, and cancel the nested questions, the option gets deselected and the questionnaire as a whole
     stays in an incomplete state
 */

class TestAppUITests: XCTestCase, @unchecked Sendable {
    @MainActor private(set) var app: XCUIApplication! // swiftlint:disable:this implicitly_unwrapped_optional
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        MainActor.assumeIsolated {
            app = XCUIApplication()
            continueAfterFailure = false
        }
    }
    
    @MainActor
    func launchAppAndStartTestQuestionnaire(named questionnaireTitle: String) {
        launchAppAndGoToOtherTest(named: questionnaireTitle)
        XCTAssert(app.navigationBars[questionnaireTitle].waitForExistence(timeout: 10))
    }

    @MainActor
    func launchAppAndGoToOtherTest(named testName: String) {
        let testsButton = app.navigationBars.buttons["Tests"]
        XCTAssert(app.launchAndWait(for: testsButton))
        testsButton.tap()
        let testButton = app.buttons[testName]
        XCTAssert(testButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        testButton.tap()
    }
}
