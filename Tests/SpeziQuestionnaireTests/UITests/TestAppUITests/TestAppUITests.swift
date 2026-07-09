//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import XCTest

/*
 IDEAS:
 - test that when you select an MC option w/ follow up questions, and cancel the nested questions, the option gets deselected and the questionnaire as a whole
     stays in an incomplete state
 */

class TestAppUITests: XCTestCase, @unchecked Sendable {
    private let timeout: TimeInterval = 10

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
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: timeout))
        XCTAssert(app.navigationBars["Spezi Questionnaire"].waitForExistence(timeout: timeout))
        tapNavigationBarButton("Tests")
        XCTAssert(app.navigationBars["Questionnaire Tests"].waitForExistence(timeout: timeout))
        tapButton(questionnaireTitle, scrolling: true)
        waitForQuestionnaireSheet()
    }
    
    @MainActor
    func launchAppAndGoToOtherTest(named testName: String) {
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: timeout))
        XCTAssert(app.navigationBars["Spezi Questionnaire"].waitForExistence(timeout: timeout))
        tapNavigationBarButton("Tests")
        XCTAssert(app.navigationBars["Questionnaire Tests"].waitForExistence(timeout: timeout))
        tapButton(testName, scrolling: true)
    }

    @MainActor
    func launchAppAndLoadPredefinedQuestionnaire(named questionnaireName: String) {
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: timeout))
        XCTAssert(app.staticTexts["Surveys"].waitForExistence(timeout: timeout))
        XCTAssert(app.staticTexts["Completed, 0"].waitForExistence(timeout: timeout))
        tapButton("Pick Predefined Questionnaire")
        XCTAssert(app.navigationBars["Pick Questionnaire"].waitForExistence(timeout: timeout))
        tapButton(questionnaireName, scrolling: true)
        XCTAssert(app.buttons["Start Questionnaire (Spezi Impl)"].waitForExistence(timeout: timeout))
    }

    @MainActor
    func tapButton(_ title: String, scrolling: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[title].firstMatch
        if scrolling {
            waitForHittableElement(button, scrolling: true)
        }
        XCTAssert(button.waitForExistence(timeout: timeout), "Missing button: \(title)", file: file, line: line)
        XCTAssert(
            button.wait(for: \.isHittable, toEqual: true, timeout: timeout),
            "Button is not hittable: \(title)",
            file: file,
            line: line
        )
        button.tap()
    }

    @MainActor
    func waitForQuestionnaireSheet(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssert(
            app.otherElements["SpeziQuestionnaireNavStack"].waitForExistence(timeout: timeout),
            "Questionnaire sheet did not appear.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func tapNavigationBarButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.navigationBars.buttons[title]
        XCTAssert(button.waitForExistence(timeout: timeout), "Missing navigation bar button: \(title)", file: file, line: line)
        XCTAssert(
            button.wait(for: \.isHittable, toEqual: true, timeout: timeout),
            "Navigation bar button is not hittable: \(title)",
            file: file,
            line: line
        )
        button.tap()
    }

    @MainActor
    private func waitForHittableElement(_ element: XCUIElement, scrolling: Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && (!element.exists || !element.isHittable) {
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                break
            }
            if scrolling {
                app.swipeUp()
            }
        }
    }
}


func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}
