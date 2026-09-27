//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct BlockingCardHighlight: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isBlocking: Bool

    private var tint: Color {
        isBlocking ? .blockingTint(for: colorScheme) : .clear
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.listRowBackground(background(over: Color(uiColor: .secondarySystemGroupedBackground)))
        #elseif os(macOS)
        content.listRowBackground(background(over: Color(nsColor: .controlBackgroundColor)))
        #else
        content
        #endif
    }

    /// The mark comes with the message and goes at the pace an answer is confirmed, on an animation of its own:
    /// an answer reaches the row without a transaction to ride on.
    private func background(over base: Color) -> some View {
        base.overlay(tint).animation(isBlocking ? SelectionFeedback.growth : SelectionFeedback.confirmation, value: isBlocking)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
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
