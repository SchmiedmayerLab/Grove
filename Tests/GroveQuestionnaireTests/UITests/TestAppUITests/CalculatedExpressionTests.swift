//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


/// Items whose answers the questionnaire calculates rather than asks for.
final class CalculatedExpressionTests: TestAppUITests, @unchecked Sendable {
    /// A hidden item converts the participant's answer into another unit: only the mmol/L question is
    /// asked, and the submitted response carries both the mmol/L answer and the mg/dL value calculated from it.
    @MainActor
    func testHiddenItemConvertsAnAnswerIntoItsOwnUnit() throws {
        launchAppAndStartFHIRExample("Unit Conversion Example")
        XCTAssert(questionnaire.question("glucose-mmol").waitUntilAsked())
        XCTAssertFalse(questionnaire.question("glucose-mg-dl").element.exists, "a hidden item is never rendered")

        try questionnaire.question("glucose-mmol").enterNumber(5.5)
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertFalse(questionnaire.question("glucose-mg-dl").element.exists, "calculating its value does not reveal it")
        XCTAssertEqual(questionnaire.offeredAction, .submit)
        questionnaire.submit()
        XCTAssert(questionnaire.waitUntilDismissed())

        assertResponseWasCollected(from: "Unit Conversion Example")
        tap(app.buttons["Response:Unit Conversion Example"])
        XCTAssert(app.navigationBars["Questionnaire Response"].waitForExistence(timeout: 10))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "ResponseItem:glucose-mg-dl").firstMatch.waitForExistence(timeout: 10))
        // 5.5 mmol/L × 18.0156 = 99.0858 mg/dL; the prefix leaves room for how the decimal is printed.
        let converted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "99.08", "mg/dL"))
            .firstMatch
        XCTAssert(converted.waitForExistence(timeout: 10), "the response must carry the calculated mg/dL value")
        let entered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "5.5", "mmol/L"))
            .firstMatch
        XCTAssert(entered.exists, "the response must keep the participant's mmol/L answer")
    }
}
