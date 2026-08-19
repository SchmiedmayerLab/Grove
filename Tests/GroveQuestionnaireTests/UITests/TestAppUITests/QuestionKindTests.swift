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


/// The answer controls the renderer draws, and the kinds an app can bring itself.
final class QuestionKindTests: TestAppUITests, @unchecked Sendable {
    @MainActor
    func testImageAnnotationEditorSupportsDrawingAndNativeZooming() {
        launchAppAndStartExample("Annotate Image", in: .modelValues)

        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        app.buttons["OpenImageAnnotationEditor"].tap()

        let canvas = app.descendants(matching: .any)["ImageAnnotationCanvas"].firstMatch
        XCTAssert(canvas.waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Where do you feel pain or stiffness?"].exists)
        XCTAssertFalse(app.staticTexts["Region"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Move & Zoom"].exists)
        XCTAssert(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["Remove"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Undo"].exists)
        XCTAssertFalse(app.buttons["Redo"].exists)

        let painRegion = app.buttons["AnnotationRegion:Pain"]
        XCTAssert(painRegion.exists)
        XCTAssert(painRegion.isSelected)
        canvas.pinch(withScale: 2, velocity: 1)
        canvas.pinch(withScale: 0.5, velocity: -1)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
            .press(
                forDuration: 0.1,
                thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6))
        )
        XCTAssert(app.buttons["Remove"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Done"].exists)
        XCTAssert(app.buttons["Undo"].exists)
        XCTAssert(app.buttons["Redo"].exists)
        XCTAssert(app.buttons["Undo"].isEnabled)
        XCTAssertFalse(app.buttons["Redo"].isEnabled)
        app.buttons["Undo"].tap()
        XCTAssert(app.buttons["Redo"].isEnabled)
        XCTAssert(app.buttons["Close"].exists)
        app.buttons["Redo"].tap()
        XCTAssert(app.buttons["Done"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        questionnaire.tapPrimaryAction()
        assertResponseWasCollected(from: "Annotate Image")
    }


    @MainActor
    func testFileAttachments() {
        launchAppAndStartExample("File Attachment", in: .modelValues)

        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))

        questionnaire.question("t0").attachFile(from: .photoLibrary)
        let image = app.otherElements["Photos"].scrollViews.otherElements["photos_sectioned_layout"].images.firstMatch
        XCTAssert(image.waitForExistence(timeout: 30))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        do {
            let task0 = app.otherElements["Task:t0"]
            XCTAssert(
                task0.staticTexts.element(
                    matching: "identifier = %@ AND label MATCHES %@", "FileAttachmentFilename", "IMG_.*.jpeg"
                ).waitForExistence(timeout: 30)
            )
            XCTAssert(
                task0.staticTexts.element(
                    matching: "identifier = %@ AND label MATCHES %@", "FileAttachmentFilesize", ".* MB"
                ).waitForExistence(timeout: 10)
            )
        }
        XCTAssertEqual(questionnaire.question("t0").attachedFilenames.count, 1)
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
    }


    /// A coded choice that also takes an answer nobody thought to code (FHIR `open-choice`).
    @MainActor
    func testOpenChoiceTakesAFreeTextAnswer() throws {
        launchAppAndStartExample("Open Choice", in: .modelValues)
        XCTAssert(questionnaire.question("t0").waitUntilAsked())

        questionnaire.question("t0").select("Mango")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))

        // picking "Other" without writing anything is not an answer
        questionnaire.question("t0").select("Other")
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        XCTAssertFalse(questionnaire.question("t0").isSelected("Mango"))

        try questionnaire.question("t0").enterOtherAnswer("Pistachio")
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
    }


    /// The `drop-down` item control: a menu rather than a list of rows.
    @MainActor
    func testDropDownChoice() {
        launchAppAndStartExample("Question Kinds", in: .swiftDSL)
        XCTAssert(questionnaire.question("continent").waitUntilAsked())

        questionnaire.tapPrimaryAction()
        XCTAssert(questionnaire.question("continent").blockingMark.waitForExistence(timeout: 10))

        questionnaire.question("continent").chooseFromMenu("Europe")
        XCTAssert(questionnaire.question("continent").blockingMark.waitForNonExistence(timeout: 5))
        // the questions that were not answered keep their mark
        XCTAssert(questionnaire.question("flavour").isMarkedAsBlocking)
    }


    /// The custom question kind the app brings along: its validation rule is what keeps the page from continuing.
    @MainActor
    func testCustomQuestionKindValidation() {
        launchAppAndStartExample("Consent Acknowledgement", in: .modelValues)

        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        questionnaire.question("t1").answer(true)
        // the disclaimer answers itself with a "no", so the page is answered but still invalid
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        XCTAssert(questionnaire.question("t0").showsText("Must agree in order to continue in questionnaire"))

        // The app draws this kind as a plain toggle inside the question's card rather than as a
        // row of the form, so only the switch itself takes a tap — not the width of the label.
        app.otherElements["Task:t0"].switches["I Agree"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .tap()
        XCTAssertFalse(questionnaire.question("t0").showsText("Must agree in order to continue in questionnaire"))
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
    }


    /// A custom kind that collects a measurement rather than a choice, and answers only once it has one.
    @MainActor
    func testCustomQuestionKindCollectingAMeasurement() {
        launchAppAndStartExample("Stopwatch", in: .modelValues)

        XCTAssert(questionnaire.question("t0").waitUntilAsked())
        XCTAssert(questionnaire.waitUntilReadiness(.incomplete))
        XCTAssert(app.descendants(matching: .any).matching(identifier: "StopwatchElapsed").firstMatch.exists)

        let toggle = app.buttons["StopwatchToggle"]
        XCTAssertEqual(toggle.label, "Start")
        toggle.tap()
        XCTAssert(toggle.wait(for: \.label, toEqual: "Stop", timeout: 5))
        toggle.tap()
        XCTAssert(toggle.wait(for: \.label, toEqual: "Start", timeout: 5))

        // the elapsed time is only written back when the watch is stopped
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
    }
}
