//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import XCTest
private import XCTestExtensions


extension QuestionnaireSheetNavigator {
    /// The question the questionnaire asks under `linkId`.
    ///
    /// The question does not have to be on screen: everything on the returned value reads the
    /// live app, so it can be asked for before a condition elsewhere brings it into being.
    public func question(_ linkId: String) -> Question {
        Question(navigator: self, linkId: linkId)
    }
}


extension QuestionnaireSheetNavigator {
    /// One question of a questionnaire, and everything a test can do with it.
    ///
    /// Which members apply depends on what the question asks: ``select(_:timeout:file:line:)``
    /// and its neighbours answer a choice, ``enterText(_:file:line:)`` a free-text question,
    /// ``enterNumber(_:file:line:)`` a numeric one. Reaching for one that does not fit fails the
    /// test rather than quietly doing nothing. For a question kind the app brought itself, use
    /// ``element`` and query it directly.
    ///
    /// ## Topics
    ///
    /// ### Whether the Question Is Asked
    /// - ``isAsked``
    /// - ``waitUntilAsked(timeout:)``
    /// - ``waitUntilNoLongerAsked(timeout:)``
    ///
    /// ### Reading the Question
    /// - ``element``
    /// - ``scrollIntoView()``
    /// - ``text``
    /// - ``showsText(_:)``
    /// - ``progressIndicator``
    /// - ``blockingMark``
    /// - ``isMarkedAsBlocking``
    ///
    /// ### Answering a Choice
    /// - ``option(_:)``
    /// - ``isSelected(_:)``
    /// - ``select(_:timeout:file:line:)``
    /// - ``select(_:timeout:file:line:answeringFollowUp:)``
    /// - ``deselect(_:timeout:file:line:)``
    /// - ``answer(_:timeout:file:line:)``
    /// - ``chooseFromMenu(_:timeout:file:line:)``
    /// - ``enterOtherAnswer(_:labelled:file:line:)``
    ///
    /// ### Answering Text, Numbers, Dates and Files
    /// - ``enterText(_:file:line:)``
    /// - ``clearText(file:line:)``
    /// - ``enterNumber(_:file:line:)``
    /// - ``moveSlider(to:)``
    /// - ``fieldValue``
    /// - ``datePicker``
    /// - ``FileSource``
    /// - ``attachFile(from:file:line:)``
    /// - ``attachedFilenames``
    @MainActor
    public struct Question {
        /// Where a file answer comes from.
        public enum FileSource: String {
            /// The camera.
            case camera = "Take Photo"
            /// The photo library.
            case photoLibrary = "Select Photo"
            /// The Files app.
            case files = "Select File"
        }

        /// The `linkId` the questionnaire gives this question.
        public let linkId: String

        private let navigator: QuestionnaireSheetNavigator

        private var app: XCUIApplication {
            navigator.app
        }

        init(navigator: QuestionnaireSheetNavigator, linkId: String) {
            self.navigator = navigator
            self.linkId = linkId
        }

        /// Taps a control of this question, bringing it onto the screen first.
        ///
        /// The renderer scrolls a page to the question it is asking about, so this only has work
        /// to do when a test reaches past where the participant is — in either direction: a page
        /// builds a row shortly before it shows it, so reaching a control is not touching it.
        fileprivate func tap(_ element: XCUIElement) {
            navigator.scan { element.isHittable }
            element.tap()
        }
    }
}


// MARK: Whether the Question Is Asked

extension QuestionnaireSheetNavigator.Question {
    /// The card the renderer draws the question in.
    ///
    /// One question is one card, so this is also the scope every other member queries within.
    /// A follow-up sheet can put a second copy of the same question on screen; this is the one
    /// on top.
    public var element: XCUIElement {
        app.otherElements.lastMatch(identifier: "Task:\(linkId)")
    }

    /// Whether the questionnaire is asking this question right now.
    ///
    /// A question a condition has switched off, one the questionnaire declares as hidden, and
    /// one on a page the participant has not reached are all equally not asked. One further down
    /// this page is not among them, and telling the two apart takes a scroll through the page.
    public var isAsked: Bool {
        scrollIntoView()
    }

    /// Waits until the question is being asked, scrolling the page to look for it.
    @discardableResult
    public func waitUntilAsked(timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if scrollIntoView() {
                return true
            }
        } while Date() < deadline
        return false
    }

    /// Waits until the question is no longer being asked.
    @discardableResult
    public func waitUntilNoLongerAsked(timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout) -> Bool {
        element.waitForNonExistence(timeout: timeout) && !scrollIntoView()
    }
}


// MARK: Reading the Question

extension QuestionnaireSheetNavigator.Question {
    /// Everything the question says: its title and subtitle, its footer, and any message the
    /// renderer has added beneath it.
    ///
    /// Choice options are buttons rather than text; ask ``isSelected(_:)`` about those.
    public var text: [String] {
        scrollIntoView()
        return element.staticTexts.allElementsBoundByIndex.map(\.label)
    }

    /// The question's place in the run, on the questionnaires that asked for one to be shown.
    public var progressIndicator: XCUIElement {
        scrollIntoView()
        return element.staticTexts.matching(identifier: "QuestionProgress").firstMatch
    }

    /// The footer the renderer puts under a question that is keeping its page from continuing.
    ///
    /// It appears when the primary action is tapped on an unfinished page, and stays until the
    /// question is answered rather than fading, so a test never has to race it.
    public var blockingMark: XCUIElement {
        scrollIntoView()
        return element.descendants(matching: .any).matching(label: "Answer this question to continue").firstMatch
    }

    /// Whether the question is marked as a reason its page cannot continue.
    public var isMarkedAsBlocking: Bool {
        blockingMark.exists
    }

    /// Scrolls the page until the question's card is on it, and reports whether it ever was.
    ///
    /// The members that read and answer the question do this first, so a test can reach further
    /// down a page than the participant has.
    @discardableResult
    public func scrollIntoView() -> Bool {
        navigator.scan { element.exists }
    }

    /// Whether `text` appears anywhere in the question's card.
    ///
    /// This is how a test reads a validation message: a rejected answer is explained in terms
    /// of the answer, right below the question.
    public func showsText(_ text: String) -> Bool {
        scrollIntoView()
        return element.descendants(matching: .any).matching(label: text).firstMatch.exists
    }
}


// MARK: Answering a Choice

extension QuestionnaireSheetNavigator.Question {
    /// The option titled `title`, whether or not it is selected.
    public func option(_ title: String) -> XCUIElement {
        element.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option: \(title), ")).firstMatch
    }

    /// Whether the option titled `title` is selected.
    public func isSelected(_ title: String) -> Bool {
        scrollIntoView()
        return element.buttons.matching(label: "Option: \(title), Selected").firstMatch.exists
    }

    /// Selects the option titled `title`, unless it is already selected.
    ///
    /// Yes/no questions are choices too, with options titled `Yes` and `No`; ``answer(_:timeout:file:line:)``
    /// says the same thing in the caller's own terms.
    public func select(
        _ title: String,
        timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard !isSelected(title) else {
            return
        }
        scrollIntoView()
        let option = element.buttons.matching(label: "Option: \(title), Not Selected").firstMatch
        // The card can be on screen while the option is not: a long option list is realised a row
        // at a time, so reaching the question is not the same as reaching the answer.
        guard option.waitForExistence(timeout: timeout) || navigator.scan(for: { option.exists }) else {
            XCTFail("Question '\(linkId)' does not offer an option titled '\(title)'.", file: file, line: line)
            return
        }
        tap(option)
    }

    /// Selects the option titled `title`, and answers the follow-up questions it opens.
    ///
    /// A choice option can carry questions of its own; selecting it presents them on a sheet,
    /// which the closure answers. The closure gets a navigator scoped to nothing in particular —
    /// the follow-up sheet is a questionnaire page like any other, primary action included.
    public func select(
        _ title: String,
        timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line,
        answeringFollowUp: (QuestionnaireSheetNavigator) -> Void
    ) {
        select(title, timeout: timeout, file: file, line: line)
        guard navigator.waitUntilNavigationBarShows("Follow-Up: \(title)", timeout: timeout) else {
            XCTFail("Selecting '\(title)' on question '\(linkId)' did not open any follow-up questions.", file: file, line: line)
            return
        }
        answeringFollowUp(navigator)
    }

    /// Deselects the option titled `title`, if it is selected.
    public func deselect(
        _ title: String,
        timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard isSelected(title) else {
            return
        }
        scrollIntoView()
        let option = element.buttons.matching(label: "Option: \(title), Selected").firstMatch
        guard option.waitForExistence(timeout: timeout) else {
            XCTFail("Question '\(linkId)' does not offer an option titled '\(title)'.", file: file, line: line)
            return
        }
        tap(option)
    }

    /// Answers a yes/no question.
    public func answer(
        _ value: Bool,
        timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        select(value ? "Yes" : "No", timeout: timeout, file: file, line: line)
    }

    /// Picks `title` out of a drop-down question.
    public func chooseFromMenu(
        _ title: String,
        timeout: TimeInterval = QuestionnaireSheetNavigator.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        scrollIntoView()
        let dropDown = element.buttons.firstMatch
        guard dropDown.waitForExistence(timeout: timeout) else {
            XCTFail("Question '\(linkId)' has no drop-down.", file: file, line: line)
            return
        }
        tap(dropDown)
        // The menu is presented above the questionnaire rather than inside the question's card.
        let item = app.buttons.matching(label: title).firstMatch
        guard item.waitForExistence(timeout: timeout) else {
            XCTFail("The drop-down of question '\(linkId)' does not offer '\(title)'.", file: file, line: line)
            return
        }
        item.tap()
    }

    /// Selects the free-text option of an open choice and writes `text` into it.
    ///
    /// - parameter text: What to write into the option's field.
    /// - parameter label: The option's title, which the questionnaire may have renamed.
    /// - parameter file: The test source file reported when the interaction fails.
    /// - parameter line: The test source line reported when the interaction fails.
    public func enterOtherAnswer(
        _ text: String,
        labelled label: String = "Other",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        select(label, file: file, line: line)
        let field = element.textFields.firstMatch
        guard field.waitForExistence(timeout: QuestionnaireSheetNavigator.defaultTimeout) else {
            XCTFail("Selecting '\(label)' on question '\(linkId)' did not offer a field to write in.", file: file, line: line)
            return
        }
        try field.enter(value: text, options: .disableKeyboardDismiss)
        navigator.dismissKeyboard()
    }
}


// MARK: Answering Text, Numbers, Dates and Files

extension QuestionnaireSheetNavigator.Question {
    /// What the question's entry field currently holds, if it has one.
    public var fieldValue: String? {
        scrollIntoView()
        let field = element.textFields.firstMatch
        return field.exists ? field.value as? String : nil
    }

    /// The date picker of a date, time, or date-and-time question.
    ///
    /// A compact date picker is a control the participant expands and scrolls, and there is no
    /// short, reliable way to set one from a test — so this hands it over rather than pretending.
    public var datePicker: XCUIElement {
        scrollIntoView()
        return element.datePickers.firstMatch
    }

    /// The files attached to the question so far, by filename.
    public var attachedFilenames: [String] {
        scrollIntoView()
        return element.staticTexts.matching(identifier: "FileAttachmentFilename").allElementsBoundByIndex.map(\.label)
    }

    /// Writes `text` into a free-text question.
    ///
    /// Where a free-text answer is typed.
    ///
    /// A short answer is a text field and a long one a text view, so the question could be
    /// answered by either — asking for only one of them missed half the questions.
    private func freeTextField(file: StaticString, line: UInt) -> XCUIElement? {
        scrollIntoView()
        let deadline = Date().addingTimeInterval(QuestionnaireSheetNavigator.defaultTimeout)
        repeat {
            for candidate in [element.textFields.firstMatch, element.textViews.firstMatch] where candidate.exists {
                return candidate
            }
            usleep(200_000)
        } while Date() < deadline
        XCTFail("Question '\(linkId)' has no free-text field.", file: file, line: line)
        return nil
    }

    /// A free-text answer may hold newlines, so the renderer puts a checkmark above the keyboard
    /// in place of a return key; this taps it when the text is in.
    public func enterText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let editor = freeTextField(file: file, line: line) else {
            return
        }
        tap(editor)
        editor.typeText(text)
        navigator.dismissKeyboard()
    }

    /// Empties a free-text question, so that the next ``enterText(_:file:line:)`` replaces the
    /// answer rather than adding to it.
    ///
    /// Selecting the answer and deleting the selection takes a hardware keyboard the simulator
    /// may not have, and quietly deleted a single character when it did not; both editors are
    /// emptied a keystroke per character instead.
    public func clearText(file: StaticString = #filePath, line: UInt = #line) throws {
        guard let editor = freeTextField(file: file, line: line) else {
            return
        }
        if editor.elementType == .textField {
            try editor.clear(options: .disableKeyboardDismiss)
        } else {
            // A text view is not a text field, so it has no `textFieldValue`; its answer is its value.
            tap(editor)
            let written = (editor.value as? String) ?? ""
            editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: written.count))
        }
        navigator.dismissKeyboard()
    }

    /// Enters `value` into a numeric question that is drawn as a field.
    public func enterNumber(_ value: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        scrollIntoView()
        let field = element.textFields.firstMatch
        guard field.waitForExistence(timeout: QuestionnaireSheetNavigator.defaultTimeout) else {
            XCTFail("Question '\(linkId)' has no numeric field.", file: file, line: line)
            return
        }
        try field.enter(
            value: NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal),
            options: .disableKeyboardDismiss
        )
        navigator.dismissKeyboard()
    }

    /// Moves a numeric question that is drawn as a slider, where 0 is its minimum and 1 its maximum.
    public func moveSlider(to position: Double) {
        scrollIntoView()
        element.sliders.firstMatch.adjust(toNormalizedSliderPosition: position)
    }

    /// Opens the question's file picker and takes the answer from `source`.
    public func attachFile(from source: FileSource, file: StaticString = #filePath, line: UInt = #line) {
        scrollIntoView()
        tap(element.buttons["FilePickerButton"])
        let option = app.buttons.matching(label: source.rawValue).firstMatch
        // The menu item exists from the moment the menu opens, but its label takes a moment to settle.
        guard option.waitForExistence(timeout: 2) else {
            XCTFail("The file picker of question '\(linkId)' does not offer '\(source.rawValue)'.", file: file, line: line)
            return
        }
        option.tap()
    }
}


extension QuestionnaireSheetNavigator {
    /// Dismisses the keyboard through the checkmark the renderer puts above it.
    ///
    /// The number pad has no return key and a free-text field would take one as a newline, so
    /// the accessory is the only thing that reliably ends editing in a questionnaire.
    public func dismissKeyboard() {
        let accessory = app.buttons.matching(label: "Dismiss Keyboard").firstMatch
        if accessory.exists, accessory.isHittable {
            accessory.tap()
        } else {
            app.dismissKeyboard()
        }
    }
}
