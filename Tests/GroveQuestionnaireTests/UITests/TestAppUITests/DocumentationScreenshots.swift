//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire

// documentation-screenshots: copy Overview Sources/Grove/Grove.docc/Resources/Questionnaire.png

/// Walks the Heart Check-In, the Sleep Check-In and the question kinds to the states the documentation shows; run through `Scripts/documentation-screenshots.sh`.
final class DocumentationScreenshots: TestAppUITests, @unchecked Sendable {
    override func setUpWithError() throws {
        // The walk needs the app the script launched and the states it prepared; a plain test run skips it.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GROVE_DOCUMENTATION_SCREENSHOTS"] == "1",
            "Run through Scripts/documentation-screenshots.sh"
        )
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureDocumentationScreenshots() {
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssert(app.buttons["Route:Swift DSL"].waitForExistence(timeout: 10))
        open(.swiftDSL)

        // The weekly check-in shows four kinds on its first page, two of them answered.
        startExample("Heart Check-In")
        XCTAssert(questionnaire.question("energy").waitUntilAsked())
        questionnaire.question("energy").select("Good")
        questionnaire.question("symptoms").select("Swollen ankles")
        // Reaching the second card scrolled the page; the overview shows it from the top.
        app.swipeDown()
        sleep(1)
        capture("Overview")
        questionnaire.closeDiscardingAnswers()

        startExample("Sleep Check-In")
        XCTAssert(questionnaire.question("sleep-trouble").waitUntilAsked())
        questionnaire.question("sleep-trouble").answer(true)
        XCTAssert(questionnaire.question("falling-asleep").waitUntilAsked())
        questionnaire.question("falling-asleep").select("Some nights")
        questionnaire.question("waking-up").select("Most nights")
        // One question is still open, so the action marks it rather than moving on.
        questionnaire.tapPrimaryAction()
        sleep(1)
        capture("Validation")
        questionnaire.question("daytime-tiredness").select("Every night")
        sleep(1)
        capture("Score")
        questionnaire.closeDiscardingAnswers()

        // One page per family of question kinds, answered far enough to show the controls at work.
        startExample("Question Kinds")
        XCTAssert(questionnaire.question("flavour").waitUntilAsked())
        questionnaire.question("flavour").select("Mango")
        questionnaire.question("books").select("A Game of Thrones")
        questionnaire.question("agrees").answer(true)
        questionnaire.question("about").enterText("I walk to work most days.")
        questionnaire.question("continent").chooseFromMenu("Europe")
        questionnaire.question("website").enterText("https://heart.stanford.edu")
        questionnaire.dismissKeyboard()
        sleep(1)
        capture("TextAndChoice")
        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("day").waitUntilAsked())
        sleep(1)
        capture("DatesAndTimes")
        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("rating").waitUntilAsked())
        questionnaire.question("rating").moveSlider(to: 0.7)
        sleep(1)
        capture("Numbers")
        questionnaire.closeDiscardingAnswers()
        returnToRootPage()

        // Marking a region on an image, and a question kind an app defined itself.
        open(.modelValues)
        startExample("Annotate Image")
        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        sleep(2)
        capture("AnnotateImage")
        questionnaire.closeDiscardingAnswers()
        startExample("Stopwatch")
        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        sleep(1)
        capture("CustomKind")
    }

    /// Announces a state worth a picture; `Scripts/documentation-screenshots.sh` shoots the simulator on this line.
    private func capture(_ name: String) {
        print("CAPTURE \(name)")
        sleep(5)
    }
}
