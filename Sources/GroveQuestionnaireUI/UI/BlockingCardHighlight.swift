//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


private struct BlockingCardHighlight: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isBlocking: Bool

    /// A dark card takes more of the tint than a white one before it reads as marked at all.
    private var tint: Color {
        guard isBlocking else {
            return .clear
        }
        return Color.red.opacity(colorScheme == .dark ? 0.22 : 0.1)
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.listRowBackground(Color(uiColor: .secondarySystemGroupedBackground).overlay(tint))
        #elseif os(macOS)
        content.listRowBackground(Color(nsColor: .controlBackgroundColor).overlay(tint))
        #else
        content
        #endif
    }
}


extension View {
    /// Marks a question while it is what keeps the page from continuing.
    ///
    /// The mark stays for as long as the question is unanswered or invalid rather than flashing
    /// once, because the participant has to be able to find it again after scrolling past it.
    /// It is the card's own background rather than a shape drawn over it, so it takes the card's
    /// inset, corner radius and clipping from the list instead of from numbers of our own —
    /// guessed insets left an outlined box floating inside the card.
    func blockingCardHighlight(_ isBlocking: Bool) -> some View {
        modifier(BlockingCardHighlight(isBlocking: isBlocking))
    }
}
