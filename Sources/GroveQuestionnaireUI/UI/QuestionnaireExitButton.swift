//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The Close button, and the confirmation it puts in the way of losing answers.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuestionnaireExitButton: View {
    /// What leaving would cost the participant, and what can be offered instead of leaving.
    enum Stakes {
        /// Nothing has been entered, so closing costs nothing and asks nothing.
        case nothingToLose
        /// Answers would be discarded, this many of that many questions in.
        case losesAnswers(answered: Int, total: Int)
        /// Every question has been answered, so leaving can hand the answers off instead.
        case canSubmit
        /// Leaving de-selects the option these follow-up questions were asked for.
        case discardsFollowUps(optionTitle: String)
    }

    /// What the participant chose to do about the answers they have.
    enum Outcome {
        case submit
        case discard
    }

    static var placement: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }

    let stakes: Stakes
    let isProcessing: Bool
    let handOff: @MainActor (Outcome) -> Void

    @State private var showConfirmation = false

    var body: some View {
        button
            .disabled(isProcessing)
            .accessibilityIdentifier("CloseQuestionnaire")
            .confirmationDialog(
                Text(title),
                isPresented: $showConfirmation,
                titleVisibility: .visible,
                actions: { actions },
                message: {
                    if let message {
                        Text(message)
                    }
                }
            )
    }

    @ViewBuilder private var button: some View {
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            Button(role: .close, action: attemptExit)
        } else {
            Button(action: attemptExit) {
                Image(systemName: "xmark")
                    .accessibilityLabel(LocalizedStringResource("Close", bundle: .module))
            }
        }
    }

    private var title: LocalizedStringResource {
        switch stakes {
        case .nothingToLose, .losesAnswers:
            LocalizedStringResource("Your answers won't be saved.", bundle: .module)
        case .canSubmit:
            LocalizedStringResource("You've answered every question.", bundle: .module)
        case .discardsFollowUps:
            LocalizedStringResource("Discard Nested Responses", bundle: .module)
        }
    }

    private var message: LocalizedStringResource? {
        switch stakes {
        case .nothingToLose, .canSubmit:
            nil // there is nothing to confirm, or the title already says it
        case let .losesAnswers(answered, total):
            LocalizedStringResource("You've answered \(answered) of \(total) questions.", bundle: .module)
        case .discardsFollowUps(let optionTitle):
            LocalizedStringResource(
                "This will de-select the '\(optionTitle)' option and discard all responses below.",
                bundle: .module
            )
        }
    }

    @ViewBuilder private var actions: some View {
        if case .canSubmit = stakes {
            // Someone deliberately leaving a finished questionnaire should not be handed one more screen.
            Button {
                handOff(.submit)
            } label: {
                Text("Submit Answers", bundle: .module)
            }
        }
        Button(role: .destructive) {
            handOff(.discard)
        } label: {
            Text("Discard Answers", bundle: .module)
        }
        Button(role: .cancel, action: {}) {
            Text("Keep Answering", bundle: .module)
        }
    }

    private func attemptExit() {
        guard case .nothingToLose = stakes else {
            showConfirmation = true
            return
        }
        // Nothing has been entered, so there is nothing to warn about.
        handOff(.discard)
    }
}
