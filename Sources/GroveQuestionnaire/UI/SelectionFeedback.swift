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
/// plays a brief confirmation first, and leaves just before it has settled so that the mark and the
/// page read as one movement rather than two.
@available(iOS 18, macOS 15, watchOS 11, *)
enum SelectionFeedback {
    /// Eased out rather than sprung, so the mark arrives at speed and settles: the fast start is what
    /// makes answering feel immediate, and it is also what lets the page follow this soon after.
    static let confirmation: Animation = .easeOut(duration: 0.14)
    /// Clearing the option the participant is moving away from is not the confirmation, so it
    /// gets out of the way rather than being watched.
    static let deselection: Animation = .easeOut(duration: 0.09)
    /// Short enough that the mark and the page read as one movement rather than two.
    static let scroll: Animation = .snappy(duration: 0.2)
    /// The page leaves before the mark has quite settled, so the two overlap into one movement
    /// instead of queueing.
    static let advanceDelay: TimeInterval = 0.08

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
        // Moving on is timed against the confirmation rather than driven by its completion
        // handler: where there is no animation to complete — a UI test host among them — that
        // handler never runs, and the participant is left on a page that should have moved.
        withAnimation(confirmation, apply)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(advanceDelay))
            advance()
        }
    }
}
