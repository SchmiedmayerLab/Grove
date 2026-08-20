//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


extension QuestionnaireSheetNavigator {
    /// How far the navigator scrolls one way before giving up on finding something.
    private static let maximumScanSwipes = 12

    /// Scrolls the page looking for something, and stops the moment it is there.
    ///
    /// A `Form` builds only the rows around the fold, so anything further down the page than it
    /// has been scrolled is not in the accessibility tree at all. Scanning is what tells a question
    /// the questionnaire is not asking from one it has not built yet, and it leaves it on screen.
    func scan(for isFound: () -> Bool) -> Bool {
        guard !isFound() else {
            return true
        }
        if scroll({ $0.swipeUp() }, lookingFor: isFound) {
            return true
        }
        // A page that would not move up is at its foot, which is exactly when everything it is
        // hiding is above.
        return scroll(dragDown, lookingFor: isFound)
    }

    /// Scrolls one way until `isFound` holds or the page stops moving.
    ///
    /// The page is looked up again for every swipe: a run that hands itself off mid-scan takes its
    /// page with it, and scanning for something a page no longer has is not a failure.
    private func scroll(_ swipe: (XCUIElement) -> Void, lookingFor isFound: () -> Bool) -> Bool {
        var lastSeen = visibleText
        for _ in 0..<Self.maximumScanSwipes {
            let page = section
            guard page.exists else {
                return false
            }
            swipe(page)
            if isFound() {
                return true
            }
            let seen = visibleText
            guard seen != lastSeen else {
                return false
            }
            lastSeen = seen
        }
        return false
    }

    /// Scrolls the page back up by a third of itself, gently enough to leave the sheet alone.
    ///
    /// Dragging a page down is the sheet's own dismissal gesture wherever the page has nowhere left
    /// to go, and a `swipeDown()` throws the questionnaire away rather than scrolling it. A short
    /// drag let go of at rest scrolls a page that has somewhere to go and rubber-bands one that has not.
    private func dragDown(_ page: XCUIElement) {
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(
                forDuration: 0.1,
                thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
    }
}
