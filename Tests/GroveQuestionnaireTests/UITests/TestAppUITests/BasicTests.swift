//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveQuestionnaire


final class BasicTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testGroveQuestionnaire() {
        let app = XCUIApplication()
        let pickQuestionnaireButton = app.buttons["Pick Predefined Questionnaire"]
        XCTAssert(app.launchAndWait(for: pickQuestionnaireButton))

        XCTAssert(app.staticTexts["Surveys"].exists)
        XCTAssert(app.staticTexts["Completed, 0"].exists)

        pickQuestionnaireButton.tap()
        XCTAssert(app.navigationBars["Pick Questionnaire"].waitForExistence(timeout: 10))
        app.swipeUp()
        let gcsButton = app.buttons["GCS"]
        XCTAssert(gcsButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        gcsButton.tap()

        let startButton = app.buttons["Start Questionnaire (Grove Impl)"]
        XCTAssert(startButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        startButton.tap()
        XCTAssert(app.navigationBars["Glasgow Coma Score"].waitForExistence(timeout: 10))

        let confused = app.otherElements["Task:1.1"].staticTexts["Confused"]
        XCTAssert(confused.wait(for: \.isHittable, toEqual: true, timeout: 10))
        confused.tap()
        app.swipeUp()
        let obeysCommands = app.otherElements["Task:1.2"].staticTexts["Obeys commands"]
        XCTAssert(obeysCommands.wait(for: \.isHittable, toEqual: true, timeout: 10))
        obeysCommands.tap()
        app.swipeUp()
        XCTAssert(app.buttons["ContinueButton_canContinue=false"].waitForExistence(timeout: 2))
        XCTAssert(!app.buttons["ContinueButton_canContinue=true"].exists)
        let eyeOpening = app.otherElements["Task:1.3"].staticTexts["Eye opening to verbal command"]
        XCTAssert(eyeOpening.wait(for: \.isHittable, toEqual: true, timeout: 10))
        eyeOpening.tap()
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        XCTAssert(!app.buttons["ContinueButton_canContinue=false"].exists)

        let continueButton = app.buttons["Continue"]
        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        continueButton.tap() // go to continue page
        XCTAssert(app.otherElements["GroveQuestionnaireCompletionPage"].waitForExistence(timeout: 10))
        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        continueButton.tap() // dismiss questionnaire
        XCTAssert(app.staticTexts["Completed, 1"].waitForExistence(timeout: 10))
    }
    
    
    @MainActor
    func testGroveQuestionnaire2() {
        let app = XCUIApplication()
        let pickQuestionnaireButton = app.buttons["Pick Predefined Questionnaire"]
        XCTAssert(app.launchAndWait(for: pickQuestionnaireButton))

        XCTAssert(app.staticTexts["Surveys"].exists)
        XCTAssert(app.staticTexts["Completed, 0"].exists)

        pickQuestionnaireButton.tap()
        XCTAssert(app.navigationBars["Pick Questionnaire"].waitForExistence(timeout: 10))
        app.swipeUp()
        let gcsButton = app.buttons["GCS"]
        XCTAssert(gcsButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        gcsButton.tap()

        let startButton = app.buttons["Start Questionnaire (Grove Impl)"]
        XCTAssert(startButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        startButton.tap()
        XCTAssert(app.navigationBars["Glasgow Coma Score"].waitForExistence(timeout: 10))

        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:1.1"].waitForExistence(timeout: 10))
        navigator.task(withId: "1.1").selectOption(withTitle: "Confused")
        navigator.task(withId: "1.2").selectOption(withTitle: "Obeys commands")
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        app.swipeUp()
        navigator.task(withId: "1.3").selectOption(withTitle: "Eye opening to verbal command")
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        XCTAssertTrue(navigator.isContinueButtonEnabled)
        navigator.goToNextSection()
        XCTAssert(app.otherElements["GroveQuestionnaireCompletionPage"].waitForExistence(timeout: 10))
        XCTAssert(navigator.isAtCompletionPage)
        navigator.goToNextSection() // will dismiss the questionnaire
        XCTAssert(app.staticTexts["Completed, 1"].waitForExistence(timeout: 10))
    }
    
    
    @MainActor
    func testSimpleNumberEntry() throws {
        launchAppAndStartTestQuestionnaire(named: "Simple Number Entry")
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.buttons["ContinueButton_canContinue=false"].waitForExistence(timeout: 10))
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        try navigator.task(withId: "t0").enterValue(5)
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        try navigator.task(withId: "t1").enterValue(7)
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        XCTAssertTrue(navigator.isContinueButtonEnabled)
    }
    
    
    @MainActor
    func testExternalResponsesObject() {
        launchAppAndGoToOtherTest(named: "External Response Object")
        let firstQuestionnaireButton = app.buttons["Show Questionnaire (1)"]
        let secondQuestionnaireButton = app.buttons["Show Questionnaire (2)"]
        XCTAssert(firstQuestionnaireButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssert(firstQuestionnaireButton.isEnabled)
        XCTAssert(secondQuestionnaireButton.exists)
        XCTAssertFalse(secondQuestionnaireButton.isEnabled)

        firstQuestionnaireButton.tap()
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:t1"].waitForExistence(timeout: 10))

        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))
        
        navigator.task(withId: "t1").selectOption(withTitle: "Mango")
        XCTAssert(app.otherElements["Task:t1"].buttons["Option: Mango, Selected"].waitForExistence(timeout: 10))
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
        XCTAssertTrue(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))

        navigator.goToNextSection()
        XCTAssert(app.otherElements["GroveQuestionnaireCompletionPage"].waitForExistence(timeout: 10))
        XCTAssert(navigator.isAtCompletionPage)
        navigator.goToNextSection() // will dismiss the questionnaire

        XCTAssert(app.otherElements["Task:t1"].waitForNonExistence(timeout: 10))
        XCTAssert(secondQuestionnaireButton.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        XCTAssert(firstQuestionnaireButton.exists)
        XCTAssert(firstQuestionnaireButton.isEnabled)
        secondQuestionnaireButton.tap()

        // we can reuse the navigator
        XCTAssert(app.otherElements["Task:t1"].buttons["Option: Mango, Selected"].waitForExistence(timeout: 10))
        XCTAssertTrue(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
    }
}
