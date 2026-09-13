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

    /// Where the page stands once it has come to rest: what it has built, and where its first line sits.
    ///
    /// The text alone cannot tell a short scroll from none, a page builds its rows well ahead of the fold;
    /// the first line's frame can. Read at rest, so a bounce on the way back is not mistaken for a move.
    private var pageAtRest: (texts: [String], firstLine: CGRect) {
        var snapshot = pageSnapshot
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.1)
            let settled = pageSnapshot
            guard settled != snapshot else {
                return settled
            }
            snapshot = settled
        }
        return snapshot
    }

    /// A page that is gone has no first line; asking a missing element for its frame would fail the test.
    private var pageSnapshot: (texts: [String], firstLine: CGRect) {
        let firstLine = section.staticTexts.firstMatch
        return (visibleText, firstLine.exists ? firstLine.frame : .zero)
    }

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

    /// Whether a tap on `element` lands on it.
    ///
    /// The page scrolls under its navigation bar, and a row peeking out from beneath the bar still
    /// reports itself hittable while the tap goes to the bar.
    func isReachable(_ element: XCUIElement) -> Bool {
        element.isHittable && element.frame.minY >= navigationBar.frame.maxY
    }

    /// Scrolls one way until `isFound` holds or the page stops moving.
    ///
    /// The page is looked up again for every swipe: a run that hands itself off mid-scan takes its
    /// page with it, and scanning for something a page no longer has is not a failure.
    private func scroll(_ swipe: (XCUIElement) -> Void, lookingFor isFound: () -> Bool) -> Bool {
        var lastSeen = pageAtRest
        for _ in 0..<Self.maximumScanSwipes {
            let page = section
            guard page.exists else {
                return false
            }
            swipe(page)
            if isFound() {
                return true
            }
            let seen = pageAtRest
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
