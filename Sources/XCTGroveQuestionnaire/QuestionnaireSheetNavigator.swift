//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import XCTest


/// Answers a `QuestionnaireSheet` from a UI test.
///
/// A navigator is a handle on the running app rather than a snapshot of it: every member reads the
/// questionnaire as it is at that moment, so one navigator lasts a whole run — across pages,
/// follow-up sheets, and the completion page.
///
/// ```swift
/// let questionnaire = QuestionnaireSheetNavigator(app)
/// app.buttons["Answer the GAD-7"].tap()
/// XCTAssert(questionnaire.waitUntilPresented())
///
/// questionnaire.question("q1").select("Several days")
/// questionnaire.question("q2").select("Not at all")
/// questionnaire.submit()
/// questionnaire.finish()
/// ```
///
/// Everything here is driven through the accessibility identifiers and labels the renderer
/// publishes, so the same code works against any questionnaire, however it was authored.
///
/// ## Topics
///
/// ### Finding the Questionnaire
/// - ``isPresented``
/// - ``waitUntilPresented(timeout:)``
/// - ``waitUntilDismissed(timeout:)``
/// - ``section``
///
/// ### Reading the Page
/// - ``navigationBar``
/// - ``navigationBarShows(_:)``
/// - ``waitUntilNavigationBarShows(_:timeout:)``
/// - ``sectionIntro``
/// - ``progressIndicator``
/// - ``visibleText``
/// - ``showsText(_:)``
///
/// ### The Questions
/// - ``question(_:)``
/// - ``Question``
///
/// ### The Primary Action
/// - ``primaryAction``
/// - ``Action``
/// - ``offeredAction``
/// - ``Readiness``
/// - ``readiness``
/// - ``isReadyToAdvance``
/// - ``waitUntilReadiness(_:timeout:)``
/// - ``waitUntilOffering(_:timeout:)``
///
/// ### Moving Through the Questionnaire
/// - ``advance(timeout:file:line:)``
/// - ``submit(timeout:file:line:)``
/// - ``tapPrimaryAction()``
/// - ``goBack(timeout:file:line:)``
/// - ``scrollDown()``
/// - ``scrollToPrimaryAction()``
///
/// ### Finishing
/// - ``completionPage``
/// - ``isAtCompletionPage``
/// - ``waitUntilAtCompletionPage(timeout:)``
/// - ``finish(timeout:file:line:)``
///
/// ### Leaving Early
/// - ``closeButton``
/// - ``ExitChoice``
/// - ``isShowingExitConfirmation``
/// - ``exitOption(_:)``
/// - ``close(timeout:file:line:)``
/// - ``close(choosing:timeout:file:line:)``
/// - ``closeDiscardingAnswers(timeout:)``
@MainActor
public struct QuestionnaireSheetNavigator {
    /// What the primary action is currently offering to do.
    ///
    /// The renderer pins one button to the bottom of every page, and what it says is a fact
    /// about where the page sits in the questionnaire.
    public enum Action: String {
        /// More pages follow this one.
        case `continue` = "Continue"
        /// The last page of a questionnaire whose answers are handed to the app.
        case submit = "Submit"
        /// The app has the answers and has not finished with them yet.
        case submitting = "Submitting…"
        /// The last page of a questionnaire that hands nothing off, and the completion page's own button.
        case done = "Done"
    }

    /// What a page reports about the answers it is holding.
    public enum Readiness: String {
        /// Every question that has to be answered is answered, and every answer passes its rules.
        case ready = "Ready"
        /// Something on the page is missing or invalid.
        case incomplete = "Incomplete"
    }

    /// What the participant can choose when they close a questionnaire that holds answers.
    public enum ExitChoice: String {
        /// Offered in place of discarding when every remaining question has been answered.
        case submitAnswers = "Submit Answers"
        /// Leaves, and throws the answers away.
        case discardAnswers = "Discard Answers"
        /// Stays on the page.
        case keepAnswering = "Keep Answering"
    }

    /// How long the navigator waits for the app to catch up, unless a call says otherwise.
    public static let defaultTimeout: TimeInterval = 10

    /// The app the questionnaire is being answered in.
    public let app: XCUIApplication

    /// Creates a navigator for the questionnaire presented in `app`.
    public init(_ app: XCUIApplication) {
        self.app = app
    }
}


// MARK: Finding the Questionnaire

extension QuestionnaireSheetNavigator {
    /// The navigation stack that owns the complete questionnaire run.
    var questionnaireRoot: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "GroveQuestionnaireNavStack").firstMatch
    }

    /// The scrolling content of the section on screen.
    ///
    /// A section is drawn as a `Form`, whose element type differs between OS versions, so this
    /// deliberately matches any element type.
    public var section: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "GroveQuestionnaireSection").firstMatch
    }

    /// The element that scrolls the current page.
    ///
    /// SwiftUI can omit a `Form`'s accessibility identifier when the form is the sole page in its
    /// navigation stack. The stack remains a collection view in that case and provides the same
    /// scrolling surface.
    var scrollablePage: XCUIElement {
        section.exists ? section : questionnaireRoot
    }

    /// Whether any page of the questionnaire — a section, or the completion page — is on screen.
    public var isPresented: Bool {
        questionnaireRoot.exists
    }

    /// Waits until the questionnaire is on screen.
    @discardableResult
    public func waitUntilPresented(timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        questionnaireRoot.waitForExistence(timeout: timeout)
    }

    /// Waits until the questionnaire has gone, which is what a handed-off or discarded run looks like.
    @discardableResult
    public func waitUntilDismissed(timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        questionnaireRoot.waitForNonExistence(timeout: timeout)
    }
}


// MARK: Reading the Page

extension QuestionnaireSheetNavigator {
    /// The navigation bar of the page on screen.
    ///
    /// A questionnaire runs in a navigation stack of its own, and a follow-up question stacks a
    /// second one on top, so the last bar is the one the participant can see.
    public var navigationBar: XCUIElement {
        app.navigationBars.allElementsBoundByIndex.last ?? app.navigationBars.firstMatch
    }

    /// The section's own text, above the questions, on every page whose section carries one.
    public var sectionIntro: XCUIElement {
        app.staticTexts["SectionIntro"]
    }

    /// The first "Question n of m" on the page, on the questionnaires that asked to be counted.
    ///
    /// Every question carries its own; ask ``Question/progressIndicator`` about a particular one.
    public var progressIndicator: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "QuestionProgress").firstMatch
    }

    /// Everything the page currently says, top to bottom.
    ///
    /// Choice options are buttons rather than text, so they are not in here; ask the question
    /// they belong to about those.
    public var visibleText: [String] {
        scrollablePage.staticTexts.allElementsBoundByIndex.map(\.label)
    }

    /// Whether `text` appears anywhere on the page, above or below the fold.
    public func showsText(_ text: String) -> Bool {
        scan { scrollablePage.staticTexts.matching(label: text).firstMatch.exists }
    }

    /// Whether the navigation bar carries `text`, as the page's title or as its subtitle.
    ///
    /// The renderer names a page by a short name (SDC `shortText`) alone: the sole group's if the
    /// page has one, else the section's, else the questionnaire's own title. The questionnaire's
    /// title is the subtitle wherever it is not already the name — and only the newest OS versions
    /// draw a subtitle, so a test should not insist on seeing both.
    public func navigationBarShows(_ text: String) -> Bool {
        navigationBar.staticTexts.matching(label: text).firstMatch.exists
    }

    /// Waits for the navigation bar to carry `text`.
    @discardableResult
    public func waitUntilNavigationBarShows(_ text: String, timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        navigationBar.staticTexts.matching(label: text).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Scrolls the page down by roughly one screen.
    ///
    /// There is no counterpart: dragging a page down that has nowhere left to go takes the sheet
    /// with it, so scrolling back up belongs to the scan, which knows where to stop.
    public func scrollDown() {
        app.swipeUp()
    }

    /// Scrolls until the page's action is on screen.
    ///
    /// The action is the last row of the form rather than chrome pinned over it, so on a long page
    /// it is not in the accessibility tree until the list has realised that far.
    @discardableResult
    public func scrollToPrimaryAction() -> Bool {
        scan { primaryAction.isHittable }
    }
}


// MARK: The Primary Action

extension QuestionnaireSheetNavigator {
    /// The one prominent button at the foot of the page on screen.
    ///
    /// Every page in the stack keeps its own, and a follow-up question stacks another sheet on
    /// top of them all, so the last match is the one the participant can reach.
    public var primaryAction: XCUIElement {
        app.buttons.lastMatch(identifier: "PrimaryAction")
    }

    /// The primary action, brought onto the screen first.
    ///
    /// The action is the page's last row rather than chrome pinned over it, so an unscrolled page
    /// would otherwise report no action at all rather than the one it has.
    private var reachablePrimaryAction: XCUIElement {
        scrollToPrimaryAction()
        return primaryAction
    }

    /// What the primary action is offering to do, read from what it says.
    public var offeredAction: Action? {
        Action(rawValue: reachablePrimaryAction.label)
    }

    /// What the page reports about the answers it is holding.
    ///
    /// The button stays enabled either way — it has to be, to be able to explain what is
    /// missing — so readiness rides on the accessibility value rather than on `isEnabled`.
    public var readiness: Readiness? {
        (reachablePrimaryAction.value as? String).flatMap(Readiness.init(rawValue:))
    }

    /// Whether the page would move on if the primary action were tapped now.
    public var isReadyToAdvance: Bool {
        readiness == .ready
    }

    /// Waits until the page reports `readiness`.
    @discardableResult
    public func waitUntilReadiness(_ readiness: Readiness, timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        reachablePrimaryAction.wait(forValue: readiness.rawValue, timeout: timeout)
    }

    /// Waits until the primary action offers `action`.
    @discardableResult
    public func waitUntilOffering(_ action: Action, timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        reachablePrimaryAction.wait(for: \.label, toEqual: action.rawValue, timeout: timeout)
    }
}


// MARK: Moving Through the Questionnaire

extension QuestionnaireSheetNavigator {
    /// Moves on to the next page, once the page reports itself ready.
    ///
    /// This is the same tap on every page: whether the button reads `Continue` or `Submit` is a
    /// fact about the page, not about the tap.
    public func advance(
        timeout: TimeInterval = Self.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard waitUntilReadiness(.ready, timeout: timeout) else {
            XCTFail("The page is not ready to advance; it reports '\(readiness?.rawValue ?? "nothing")'.", file: file, line: line)
            return
        }
        reachablePrimaryAction.tap()
    }

    /// Hands the answers to the app, having checked that this really is the last page.
    public func submit(
        timeout: TimeInterval = Self.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let action = offeredAction, action != .continue else {
            XCTFail("The page still offers '\(primaryAction.label)', so it is not the last one.", file: file, line: line)
            return
        }
        advance(timeout: timeout, file: file, line: line)
    }

    /// Taps the primary action whatever state the page is in.
    ///
    /// Tapping an unfinished page is how a test reaches the marks: the renderer answers the tap
    /// by marking every question that blocks the page and bringing the first of them into view.
    public func tapPrimaryAction() {
        reachablePrimaryAction.tap()
    }

    /// Returns to the previous page.
    ///
    /// The completion page has no way back, and neither has a questionnaire in `sequential`
    /// entry mode; both hide the button, and this says so rather than guessing.
    public func goBack(
        timeout: TimeInterval = Self.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let backButtons = app.navigationBars.buttons.matching(identifier: "BackButton")
        _ = backButtons.firstMatch.waitForExistence(timeout: timeout)
        let backButton = backButtons.allElementsBoundByIndex.last { $0.isHittable }
        guard let backButton else {
            XCTFail("The questionnaire offers no way back from this page.", file: file, line: line)
            return
        }
        backButton.tap()
    }
}


// MARK: Finishing

extension QuestionnaireSheetNavigator {
    /// The page a questionnaire ends on, when it was asked for one.
    public var completionPage: XCUIElement {
        app.otherElements["GroveQuestionnaireCompletionPage"]
    }

    /// Whether the completion page is the page on screen.
    public var isAtCompletionPage: Bool {
        completionPage.exists
    }

    /// Waits until the completion page is on screen.
    @discardableResult
    public func waitUntilAtCompletionPage(timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        completionPage.waitForExistence(timeout: timeout)
    }

    /// Taps `Done` on the completion page, which is what finally hands the answers over.
    public func finish(
        timeout: TimeInterval = Self.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard waitUntilAtCompletionPage(timeout: timeout) else {
            XCTFail("The questionnaire is not at its completion page.", file: file, line: line)
            return
        }
        reachablePrimaryAction.tap()
    }
}


// MARK: Leaving Early

extension QuestionnaireSheetNavigator {
    /// The Close button of the page on screen.
    public var closeButton: XCUIElement {
        app.buttons.lastMatch(identifier: "CloseQuestionnaire")
    }

    /// Whether the confirmation the Close button puts in the way of losing answers is on screen.
    ///
    /// Keyed on Discard rather than Keep Answering: presented as a popover the confirmation
    /// drops its cancel button, because tapping outside is what dismisses a popover.
    public var isShowingExitConfirmation: Bool {
        exitOption(.discardAnswers).exists
    }

    /// One of the choices the exit confirmation offers.
    ///
    /// ``ExitChoice/submitAnswers`` is only there when there is nothing left to answer, and
    /// ``ExitChoice/keepAnswering`` only when the confirmation is not a popover — use
    /// ``keepAnswering(timeout:)`` rather than tapping it directly.
    public func exitOption(_ choice: ExitChoice) -> XCUIElement {
        app.buttons.matching(label: choice.rawValue).firstMatch
    }

    /// Dismisses the exit confirmation, leaving the answers as they are.
    public func keepAnswering(timeout: TimeInterval = 2) {
        let option = exitOption(.keepAnswering)
        if option.waitForExistence(timeout: timeout) {
            option.tap()
        } else {
            // A popover has no cancel button; tapping away from it is the way back.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        }
        _ = exitOption(.discardAnswers).waitForNonExistence(timeout: timeout)
    }

    /// Closes a questionnaire that has nothing to lose, which leaves without asking anything.
    public func close(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) {
        closeButton.tap()
        if exitOption(.keepAnswering).waitForExistence(timeout: timeout) {
            XCTFail("The questionnaire asked before closing; use close(choosing:) to answer it.", file: file, line: line)
        }
    }

    /// Closes the questionnaire, answering the confirmation with `choice`.
    public func close(
        choosing choice: ExitChoice,
        timeout: TimeInterval = Self.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        closeButton.tap()
        let option = exitOption(choice)
        guard option.waitForExistence(timeout: timeout) else {
            XCTFail("The exit confirmation does not offer '\(choice.rawValue)'.", file: file, line: line)
            return
        }
        option.tap()
    }

    /// Closes the questionnaire, throwing away whatever has been entered.
    ///
    /// The renderer only asks when there is something to lose, so this answers the confirmation
    /// when it appears and simply leaves when it does not — which is what a test that is only
    /// passing through a questionnaire wants.
    ///
    /// - parameter timeout: How long to give the confirmation to appear before deciding there is none.
    public func closeDiscardingAnswers(timeout: TimeInterval = 2) {
        closeButton.tap()
        let discard = exitOption(.discardAnswers)
        if discard.waitForExistence(timeout: timeout) {
            discard.tap()
        }
    }
}
