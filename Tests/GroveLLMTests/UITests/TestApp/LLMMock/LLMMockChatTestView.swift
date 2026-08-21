//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveChat
import GroveLLM
import SwiftUI


/// Drives ``LLMChatView`` with the mock session, so the view's own wiring can be tested without a provider.
///
/// ``LLMChatView`` is where the library joins a session to the chat: the stop button, the inline failure with its
/// retry, and the attach menu are all state it publishes into the environment. None of that is reachable from a unit
/// test, and it was once missing altogether — the composer drew a stop button that nothing could activate — so it is
/// exercised from here instead.
struct LLMMockChatTestView: View {
    /// The identity of the internal opening input, so the chat can keep it out of the conversation.
    private static let starterID = UUID()

    @LLMSessionProvider<LLMMockSchema> private var llm: LLMMockSession

    /// Mirrors an app that primes the model with an input the participant never wrote: the answer streams
    /// in as the first visible message of an otherwise empty conversation.
    private var startsWithHiddenInput: Bool {
        ProcessInfo.processInfo.arguments.contains("--hiddenStarter")
    }

    var body: some View {
        LLMChatView(session: $llm, attachments: [.photoLibrary, .files])
            .navigationTitle("LLM Mock Chat")
            .chatHiddenMessages(startsWithHiddenInput ? [Self.starterID] : [])
            .onAppear {
                guard startsWithHiddenInput, llm.context.isEmpty else {
                    return
                }
                llm.context.append(userMessage: "Follow the instructions to begin.", id: Self.starterID)
            }
            .toolbar {
                // The mock never fails on its own, and the failure banner is part of what this view exists to
                // cover, so the test puts the session into either failure state directly.
                ToolbarItem(placement: .primaryAction) {
                    Button("Fail") {
                        llm.state = .error(error: LLMMockChatError.transient)
                    }
                    .accessibilityIdentifier("Force Error")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Fail Hard") {
                        llm.state = .error(error: LLMMockChatError.permanent)
                    }
                    .accessibilityIdentifier("Force Fatal Error")
                }
            }
    }

    init() {
        self._llm = LLMSessionProvider(schema: LLMMockSchema())
    }
}


/// The failures the test app forces, so the banner has something to show — one of each kind.
enum LLMMockChatError: LLMError {
    /// Something that could work on a second attempt.
    case transient
    /// Something that will fail identically however often it is asked.
    case permanent

    var isRetriable: Bool {
        switch self {
        case .transient: true
        case .permanent: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .transient: "The mock session was asked to fail."
        case .permanent: "The mock session was asked to fail permanently."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .transient: nil
        case .permanent: "Nothing here can fix it; the app has to."
        }
    }
}
