//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTSpeziQuestionnaire


final class BasicTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testSpeziQuestionnaire() {
        launchAppAndLoadPredefinedQuestionnaire(named: "GCS")
        tapButton("Start Questionnaire (Spezi Impl)")
        waitForQuestionnaireSheet()
        
        XCTAssert(app.otherElements["Task:1.1"].staticTexts["Confused"].waitForExistence(timeout: 10))
        app.otherElements["Task:1.1"].staticTexts["Confused"].tap()
        app.swipeUp()
        XCTAssert(app.otherElements["Task:1.2"].staticTexts["Obeys commands"].waitForExistence(timeout: 10))
        app.otherElements["Task:1.2"].staticTexts["Obeys commands"].tap()
        app.swipeUp()
        XCTAssert(app.buttons["ContinueButton_canContinue=false"].exists)
        XCTAssert(!app.buttons["ContinueButton_canContinue=true"].exists)
        XCTAssert(app.otherElements["Task:1.3"].staticTexts["Eye opening to verbal command"].waitForExistence(timeout: 10))
        app.otherElements["Task:1.3"].staticTexts["Eye opening to verbal command"].tap()
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].exists)
        XCTAssert(!app.buttons["ContinueButton_canContinue=false"].exists)
        
        tapButton("Continue") // go to continue page
        tapButton("Continue") // dismiss questionnaire
        XCTAssert(app.staticTexts["Completed, 1"].waitForExistence(timeout: 10))
    }
    
    
    @MainActor
    func testSpeziQuestionnaire2() {
        launchAppAndLoadPredefinedQuestionnaire(named: "GCS")
        tapButton("Start Questionnaire (Spezi Impl)")
        waitForQuestionnaireSheet()
        
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:1.1"].waitForExistence(timeout: 10))
        navigator.task(withId: "1.1").selectOption(withTitle: "Confused")
        navigator.task(withId: "1.2").selectOption(withTitle: "Obeys commands")
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        app.swipeUp()
        navigator.task(withId: "1.3").selectOption(withTitle: "Eye opening to verbal command")
        XCTAssertTrue(navigator.isContinueButtonEnabled)
        navigator.goToNextSection()
        XCTAssert(navigator.isAtCompletionPage)
        navigator.goToNextSection() // will dismiss the questionnaire
        XCTAssert(app.staticTexts["Completed, 1"].waitForExistence(timeout: 10))
    }
    
    
    @MainActor
    func testSimpleNumberEntry() throws {
        launchAppAndGoToOtherTest(named: "Simple Number Entry")
        waitForQuestionnaireSheet()
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:t0"].waitForExistence(timeout: 10))
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        try navigator.task(withId: "t0").enterValue(5)
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        try navigator.task(withId: "t1").enterValue(7)
        XCTAssertTrue(navigator.isContinueButtonEnabled)
    }
    
    
    @MainActor
    func testExternalResponsesObject() {
        launchAppAndGoToOtherTest(named: "External Response Object")
        XCTAssert(app.buttons["Show Questionnaire (1)"].exists)
        XCTAssert(app.buttons["Show Questionnaire (1)"].isEnabled)
        XCTAssert(app.buttons["Show Questionnaire (2)"].exists)
        XCTAssertFalse(app.buttons["Show Questionnaire (2)"].isEnabled)
        
        app.buttons["Show Questionnaire (1)"].tap()
        let navigator = QuestionnaireSheetNavigator(app)
        
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))
        
        navigator.task(withId: "t1").selectOption(withTitle: "Mango")
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
        XCTAssertTrue(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))
        
        navigator.goToNextSection()
        XCTAssert(navigator.isAtCompletionPage)
        navigator.goToNextSection() // will dismiss the questionnaire
        
        XCTAssert(app.buttons["Show Questionnaire (1)"].exists)
        XCTAssert(app.buttons["Show Questionnaire (1)"].isEnabled)
        XCTAssert(app.buttons["Show Questionnaire (2)"].exists)
        XCTAssert(app.buttons["Show Questionnaire (2)"].isEnabled)
        app.buttons["Show Questionnaire (2)"].tap()
        
        // we can reuse the navigator
        XCTAssertTrue(navigator.task(withId: "t1").didSelectOption(withTitle: "Mango"))
        XCTAssertFalse(navigator.task(withId: "t1").didSelectOption(withTitle: "Strawberry"))
    }
}
