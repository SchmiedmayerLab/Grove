//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


final class ConditionTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testSimpleCondition() {
        launchAppAndStartTestQuestionnaire(named: "Simple Condition")
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:ice-cream"].waitForExistence(timeout: 10))

        navigator.task(withId: "ice-cream").selectOption(withTitle: "Yes")
        XCTAssert(app.otherElements["Task:ice-cream-flavor"].waitForExistence(timeout: 10))

        navigator.task(withId: "ice-cream").selectOption(withTitle: "No")
        XCTAssert(app.otherElements["Task:ice-cream-flavor"].waitForNonExistence(timeout: 2))
    }
    
    
    @MainActor
    func testCrossSectionCondition() {
        launchAppAndStartTestQuestionnaire(named: "Cross-Section Condition")
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:ice-cream"].waitForExistence(timeout: 10))

        navigator.task(withId: "ice-cream").selectOption(withTitle: "No")
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        navigator.goToNextSection()
        XCTAssert(app.staticTexts["All Done!"].waitForExistence(timeout: 10))

        navigator.returnToPreviousSection()
        XCTAssert(app.staticTexts["All Done!"].waitForNonExistence(timeout: 10))

        navigator.task(withId: "ice-cream").selectOption(withTitle: "Yes")
        navigator.goToNextSection()

        XCTAssert(app.otherElements["Task:ice-cream-flavor"].waitForExistence(timeout: 10))
        XCTAssertFalse(navigator.isContinueButtonEnabled)
        navigator.task(withId: "ice-cream-flavor").selectOption(withTitle: "Mango")
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        XCTAssertTrue(navigator.isContinueButtonEnabled)
        navigator.goToNextSection()
        XCTAssert(app.staticTexts["All Done!"].waitForExistence(timeout: 10))
    }
    
    
    /// Tests the rules that apply when evaluating conditions within a questionnaire,
    /// namely that a condition can only reference tasks that precede the task to which the condition belongs.
    @MainActor
    func testConditionRules() {
        launchAppAndStartTestQuestionnaire(named: "Test Condition Lookup Rules")
        let navigator = QuestionnaireSheetNavigator(app)
        
        XCTAssert(app.staticTexts["Section A"].waitForExistence(timeout: 10))
        XCTAssert(app.otherElements["Task:t2A"].waitForExistence(timeout: 10))
        XCTAssertFalse(navigator.task(withId: "t1A").exists)
        navigator.task(withId: "t2A").selectOption(withTitle: "Red")
        XCTAssert(app.otherElements["Task:t1A"].waitForNonExistence(timeout: 2))
        navigator.task(withId: "t2A").selectOption(withTitle: "Green")
        XCTAssert(app.otherElements["Task:t1A"].waitForNonExistence(timeout: 2))
        navigator.task(withId: "t2A").selectOption(withTitle: "Blue")
        XCTAssert(app.otherElements["Task:t1A"].waitForNonExistence(timeout: 2))
        
        let continueButton = app.buttons["Continue"]
        XCTAssert(continueButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        continueButton.tap()
        XCTAssert(app.staticTexts["Section A"].waitForNonExistence(timeout: 2))
        XCTAssert(app.staticTexts["Section B"].waitForExistence(timeout: 10))
        XCTAssert(app.otherElements["Task:t1B"].waitForExistence(timeout: 10))

        XCTAssert(app.otherElements["Task:t2B"].waitForNonExistence(timeout: 2))
        navigator.task(withId: "t1B").selectOption(withTitle: "Red")
        XCTAssert(app.otherElements["Task:t2B"].waitForNonExistence(timeout: 2))
        navigator.task(withId: "t1B").selectOption(withTitle: "Green")
        XCTAssert(app.otherElements["Task:t2B"].waitForExistence(timeout: 2))
        navigator.task(withId: "t1B").deselectOption(withTitle: "Green")
        XCTAssert(app.otherElements["Task:t2B"].waitForNonExistence(timeout: 2))
        navigator.task(withId: "t1B").selectOption(withTitle: "Green")
        XCTAssert(app.otherElements["Task:t2B"].waitForExistence(timeout: 2))
        navigator.task(withId: "t1B").selectOption(withTitle: "Blue")
        XCTAssert(app.otherElements["Task:t2B"].waitForNonExistence(timeout: 2))
    }
    
    
    @MainActor
    func testFollowUpQuestionsSkippedIfNoneEnabled() {
        launchAppAndStartTestQuestionnaire(named: "Follow-Up Tasks Skipped if None Enabled")
        let navigator = QuestionnaireSheetNavigator(app)
        XCTAssert(app.otherElements["Task:t0"].waitForExistence(timeout: 10))

        navigator.task(withId: "t0").selectOption(withTitle: "Yes")
        navigator.task(withId: "t1").selectOption(withTitle: "Option 0")
        XCTAssert(app.otherElements["Task:t1.1"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["Section 2"].waitForNonExistence(timeout: 10))

        navigator.task(withId: "t1.1").selectOption(withTitle: "Yes")
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        navigator.goToNextSection() // dismiss the nested questions sheet
        XCTAssert(app.otherElements["Task:t1.1"].waitForNonExistence(timeout: 10))
        navigator.goToNextSection() // go to next section

        XCTAssert(app.staticTexts["Section 2"].waitForExistence(timeout: 10))
        navigator.returnToPreviousSection()
        XCTAssert(app.staticTexts["Section 2"].waitForNonExistence(timeout: 10))
        XCTAssert(app.otherElements["Task:t0"].waitForExistence(timeout: 10))
        navigator.task(withId: "t0").selectOption(withTitle: "No")
        XCTAssert(app.buttons["ContinueButton_canContinue=true"].waitForExistence(timeout: 2))
        navigator.goToNextSection()
        XCTAssert(app.staticTexts["Section 2"].waitForExistence(timeout: 10))
    }
}
