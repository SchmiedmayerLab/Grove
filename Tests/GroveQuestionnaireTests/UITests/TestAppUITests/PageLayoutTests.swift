//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTGroveQuestionnaire


/// What a page says about itself: what names it, what heads its content, and how far along it is.
///
/// A short name (SDC `shortText`) names the navigation bar and nothing else does; everything the
/// author wrote reaches the page, so no page can lose a name it was given.
final class PageLayoutTests: TestAppUITests, @unchecked Sendable {
    /// A group's short name names the bar, and the text it stands for still heads the questions.
    @MainActor
    func testAGroupsShortNameNamesTheBar() {
        startPageShapes(upTo: "morning-note")

        XCTAssert(questionnaire.navigationBarShows("Mornings"))
        XCTAssert(questionnaire.showsText("Everything you do before you leave the house"))
        XCTAssertFalse(questionnaire.navigationBarShows("Everything you do before you leave the house"))
        XCTAssertFalse(questionnaire.sectionIntro.exists)
    }


    /// With no short name anywhere on the page, the instrument's own name is what the bar has.
    @MainActor
    func testWithoutAShortNameTheInstrumentNamesTheBar() {
        startPageShapes(upTo: "evening-note")

        XCTAssert(questionnaire.navigationBarShows("Page Titles"))
        XCTAssert(questionnaire.showsText("Evening wind-down"))
        XCTAssertFalse(questionnaire.navigationBarShows("Evening wind-down"))
    }


    /// A name in the bar has to describe everything under it, so two groups head themselves
    /// on the page and the section's short name takes the bar.
    ///
    /// The section's own text is a prompt rather than a name, and a prompt stops meaning anything
    /// the moment a bar cuts it — it heads the content, in full.
    @MainActor
    func testEachGroupSharingAPageHeadsItself() {
        startPageShapes(upTo: "weekday-note")

        XCTAssert(questionnaire.navigationBarShows("Your Week"))
        XCTAssert(questionnaire.showsText("Weekdays"))
        XCTAssert(questionnaire.showsText("Weekends"))
        XCTAssert(questionnaire.sectionIntro.exists)
        XCTAssertEqual(questionnaire.sectionIntro.label, "How would you describe a normal week for you?")
        XCTAssertFalse(questionnaire.navigationBarShows("How would you describe a normal week for you?"))
    }


    /// A group the author named only by its short name is headed by that name.
    ///
    /// It shares its page, so the bar is not carrying it; without this the name the author wrote
    /// would appear nowhere at all.
    @MainActor
    func testAGroupNamedOnlyByItsShortNameStillHeadsItsQuestions() {
        startPageShapes(upTo: "daytime-note")

        XCTAssert(questionnaire.showsText("Daytime"))
        XCTAssert(questionnaire.showsText("Sleep"))
        XCTAssert(questionnaire.navigationBarShows("Page Titles"))
    }


    /// The one redundancy worth suppressing: a short name that is the title, word for word.
    @MainActor
    func testAShortNameIdenticalToTheTitleIsNotRepeatedOnThePage() {
        startPageShapes(upTo: "check-in-note")

        XCTAssert(questionnaire.navigationBarShows("Check-In"))
        XCTAssertFalse(questionnaire.showsText("Check-In"))
    }


    /// A page with nothing named on it carries the instrument's name and no headings at all.
    @MainActor
    func testAPageWithNothingNamedOnIt() {
        startPageShapes(upTo: "unnamed-note")

        XCTAssert(questionnaire.navigationBarShows("Page Titles"))
        XCTAssertFalse(questionnaire.sectionIntro.exists)
    }


    /// FHIR nests groups arbitrarily, and a name at any depth reaches the page.
    ///
    /// The enclosing group heads the questions once, where they begin, rather than again above
    /// every group nested inside it.
    @MainActor
    func testAGroupInsideAGroupHeadsThePageTogetherWithIt() {
        startPageShapes(upTo: "people-note")

        XCTAssert(questionnaire.showsText("Your Household"))
        XCTAssert(questionnaire.showsText("People"))
        XCTAssert(questionnaire.showsText("Pets"))
        XCTAssertEqual(questionnaire.visibleText.count { $0 == "Your Household" }, 1)
    }


    /// The section's text captions the questions from above the first of them.
    ///
    /// That the caption is a light line outside the card rather than a card of its own is a
    /// matter of colour and weight, which the captured screenshots show and this cannot: a
    /// header and a card are the same cell, inset the same way, to an accessibility tree.
    @MainActor
    func testTheSectionsTextCaptionsTheQuestionsBelowIt() {
        launchAppAndStartExample("Sleep Check-In", in: .swiftDSL)
        XCTAssert(questionnaire.question("sleep-trouble").waitUntilAsked())

        XCTAssertEqual(questionnaire.sectionIntro.label, "Your Week")
        XCTAssert(questionnaire.sectionIntro.frame.maxY <= questionnaire.question("intro").element.frame.minY)
    }


    /// FHIR that authors no `shortText` names every bar after the instrument, and puts each
    /// group's text on the page it heads.
    @MainActor
    func testFHIRWithoutShortTextKeepsTheInstrumentInTheBar() {
        launchAppAndStartFHIRExample("Form Example")

        // the first page holds only the questionnaire's opening note, and has no group of its own
        XCTAssert(questionnaire.waitUntilReadiness(.ready))
        XCTAssertFalse(questionnaire.sectionIntro.exists)
        questionnaire.advance()

        XCTAssert(questionnaire.sectionIntro.waitForExistence(timeout: 10))
        XCTAssertEqual(questionnaire.sectionIntro.label, "Let's talk about ice cream.")
        XCTAssert(questionnaire.navigationBarShows("Form Example"))
    }


    /// A group's text is as often the stem its questions hang off as it is a name, and the stem
    /// has to stay on screen in full or the questions below it stop making sense.
    @MainActor
    func testALongGroupTextHeadsTheContentRatherThanTheBar() {
        launchAppAndStartFHIRExample("Generalized Anxiety Disorder - 7")

        XCTAssert(questionnaire.sectionIntro.waitForExistence(timeout: 10))
        XCTAssert(questionnaire.sectionIntro.label.hasPrefix("How often have you been bothered"))
        XCTAssertFalse(questionnaire.navigationBarShows(questionnaire.sectionIntro.label))
        XCTAssert(questionnaire.navigationBarShows("Generalized Anxiety Disorder - 7"))
    }


    /// Progress is off unless the questionnaire asks for it, and it numbers each question where
    /// it is asked rather than counting the participant's way through from the foot of the page.
    @MainActor
    func testQuestionProgress() {
        launchAppAndStartExample("Patient Health Questionnaire-9", in: .modelValues)
        XCTAssert(questionnaire.question("H1/T1/Q1").waitUntilAsked())

        XCTAssertEqual(questionnaire.question("H1/T1/Q1").progressIndicator.label, "Question 1 of 9")
        XCTAssertEqual(questionnaire.question("H1/T1/Q9").progressIndicator.label, "Question 9 of 9")
        // the number belongs to the question, so answering it does not renumber the page
        questionnaire.question("H1/T1/Q1").select("Not at all")
        XCTAssertEqual(questionnaire.question("H1/T1/Q1").progressIndicator.label, "Question 1 of 9")
    }


    @MainActor
    func testQuestionProgressIsAbsentUnlessAskedFor() {
        launchAppAndStartExample("GAD-7 Anxiety", in: .modelValues)
        XCTAssert(questionnaire.question("q1").waitUntilAsked())
        XCTAssertFalse(questionnaire.progressIndicator.exists)
    }


    /// Opens the example that holds one page per naming shape, and walks forward to the page
    /// that asks `linkId`.
    ///
    /// Every page of it asks instructions only, so walking forward needs no answers.
    @MainActor
    private func startPageShapes(upTo linkId: String) {
        let pages = ["morning-note", "evening-note", "weekday-note", "daytime-note", "check-in-note", "unnamed-note", "people-note"]
        launchAppAndStartExample("Page Titles", in: .modelValues, titled: "Mornings")
        for page in pages.prefix(while: { $0 != linkId }) {
            XCTAssert(questionnaire.question(page).waitUntilAsked())
            questionnaire.advance()
        }
        XCTAssert(questionnaire.question(linkId).waitUntilAsked())
    }
}
