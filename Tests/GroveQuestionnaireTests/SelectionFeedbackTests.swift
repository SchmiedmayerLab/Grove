//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveQuestionnaire
@testable import GroveQuestionnaireUI
import Testing


/// Covers the order and the arity of a selection's two halves.
///
/// How long the page waits is a property of a running animation, so it belongs to the UI tests; what is
/// checked here is that the answer is never the thing being waited for.
@Suite
@MainActor
struct SelectionFeedbackTests {
    @Test
    func theAnswerLandsAsTheParticipantTaps() {
        var events: [String] = []

        SelectionFeedback.record(
            reduceMotion: false,
            { events.append("recorded") },
            thenAdvance: { events.append("advanced") }
        )

        #expect(events.first == "recorded", "The answer has to land as the participant taps, not once the confirmation ends.")
        #expect(events.count(where: { $0 == "advanced" }) <= 1, "The page should be moved on at most once.")
    }

    @Test
    func reducedMotionMovesOnWithoutWaitingForAConfirmation() {
        var recorded = false
        var advanced = false

        SelectionFeedback.record(reduceMotion: true, { recorded = true }, thenAdvance: { advanced = true })

        #expect(recorded)
        #expect(advanced, "There is no confirmation to wait for, so nothing should hold the page back.")
    }

    @Test(arguments: [false, true])
    func anAnswerThatDoesNotAdvanceIsSimplyRecorded(reduceMotion: Bool) {
        var recorded = false

        SelectionFeedback.record(reduceMotion: reduceMotion, { recorded = true }, thenAdvance: nil)

        #expect(recorded)
    }
}
