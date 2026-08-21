//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// How a questionnaire acknowledges an answer, and when it moves the participant on.
///
/// An answer whose question scrolls away in the frame it was given in never reads as confirmed: the
/// checkmark and the question leave together, so nothing was seen to be accepted. The page therefore
/// plays a brief confirmation first and starts the scroll when that animation *ends*, rather than after
/// an interval guessed to be long enough for it.
@available(iOS 18, macOS 15, watchOS 11, *)
enum SelectionFeedback {
    /// Eased out rather than sprung, so the mark arrives at speed and settles: the fast start is what
    /// makes answering feel immediate, and it is also what lets the page follow this soon after.
    static let confirmation: Animation = .easeOut(duration: 0.14)
    /// Short enough that the mark and the page read as one movement rather than two.
    static let scroll: Animation = .snappy(duration: 0.25)

    /// Records an answer, and moves on once its confirmation has played.
    ///
    /// - Parameters:
    ///   - reduceMotion: Whether the participant has asked for less movement. There is then no
    ///     confirmation to wait for, so the page moves on straight away.
    ///   - apply: Writes the answer into the responses.
    ///   - advance: Moves the participant on. Pass `nil` for an answer that leaves them where they are —
    ///     clearing a choice, or ticking one box of several.
    @MainActor
    static func record(
        reduceMotion: Bool,
        _ apply: () -> Void,
        thenAdvance advance: (() -> Void)?
    ) {
        guard !reduceMotion else {
            apply()
            advance?()
            return
        }
        guard let advance else {
            withAnimation(confirmation, apply)
            return
        }
        // `.logicallyComplete` fires when the confirmation has finished being perceived, rather than
        // when the spring has finished settling, which would hold the page back for no visible reason.
        withAnimation(confirmation, completionCriteria: .logicallyComplete, apply) {
            advance()
        }
    }
}
