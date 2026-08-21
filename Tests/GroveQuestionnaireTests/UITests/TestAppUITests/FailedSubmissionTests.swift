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


/// Covers what happens when the app cannot accept the answers it was handed.
///
/// The contract a result handler is written against: throwing reports the failure and leaves the
/// participant on their answers. Swallowing it instead would dismiss the questionnaire as though the
/// answers had been taken, which is the one outcome nobody can recover from.
final class FailedSubmissionTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testAFailedSubmissionIsReportedAndKeepsTheAnswers() {
        app.launchArguments += ["--failSubmission"]
        launchApp()
        open(.completionFlow)
        startExample("No Completion Page", titled: "Reopenable Survey")

        questionnaire.question("flavour").select("Mango")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        questionnaire.tapPrimaryAction()

        let alert = app.alerts.firstMatch
        XCTAssert(alert.waitForExistence(timeout: 10), "A submission the app refused has to be reported.")
        alert.buttons.firstMatch.tap()

        XCTAssertFalse(questionnaire.waitUntilDismissed(timeout: 2), "The questionnaire should still be open.")
        XCTAssert(
            questionnaire.question("flavour").isSelected("Mango"),
            "The participant keeps the answers they gave, so they can try again."
        )
    }
}
