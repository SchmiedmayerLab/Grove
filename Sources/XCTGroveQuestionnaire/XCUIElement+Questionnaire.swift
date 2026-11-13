//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTest


extension XCUIElementQuery {
    /// The elements whose accessibility label is exactly `label`.
    ///
    /// The renderer identifies what a test needs to find and labels what it needs to read; a
    /// query by label is the second of those, and is spelled out rather than left to the
    /// subscript, which will happily match an identifier instead.
    func matching(label: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label == %@", label))
    }

    /// The last element carrying `identifier`.
    ///
    /// A questionnaire keeps every page it has pushed, and a follow-up question stacks a sheet
    /// on top of them all, so several pages answer to the same identifier at once. The one the
    /// participant can see is the last.
    func lastMatch(identifier: String) -> XCUIElement {
        let matches = matching(identifier: identifier)
        return matches.element(boundBy: max(matches.count - 1, 0))
    }
}


extension XCUIElementSnapshot {
    /// This element if it is a static text, then every static text beneath it, depth first: the
    /// order in which a `staticTexts` query lists them.
    @MainActor var staticTextsWithin: [any XCUIElementSnapshot] {
        (elementType == .staticText ? [self] : []) + children.flatMap(\.staticTextsWithin)
    }
}
