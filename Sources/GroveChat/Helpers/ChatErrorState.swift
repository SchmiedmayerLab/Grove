//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Reports a failed answer inline, where the answer would have been.
///
/// An alert takes the conversation away to say something went wrong; this leaves it in place, so the failure reads
/// as part of the exchange and the retry sits next to what it would retry.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatErrorView: View {
    let state: ChatErrorState

    private var message: String {
        guard let error = state.error else {
            return ""
        }
        // `LocalizedError` is what a well-behaved error uses to say something a person can act on; anything else
        // would surface as a type name, which tells the user nothing.
        if let localized = error as? any LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    /// What the user can do about it, when the error says.
    ///
    /// This carries the weight for a failure that cannot be retried: with no button to offer, the way out is the
    /// only thing left worth showing, and a banner that just states a dead end is no help at all.
    private var recovery: String? {
        (state.error as? any LocalizedError)?.recoverySuggestion
    }

    var body: some View {
        if state.error != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let recovery {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let retry = state.retry {
                    Button {
                        retry()
                    } label: {
                        Label {
                            Text("Try Again", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}


/// A failed attempt at an answer, shown in the conversation rather than over it.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatErrorState {
    let error: (any Error)?
    var retry: (@MainActor @Sendable () -> Void)?
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// The failure to report at the end of the conversation, if any.
    @Entry var chatErrorState = ChatErrorState(error: nil)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Reports a failed answer inline, at the end of the conversation.
    ///
    /// Pass `nil` once the failure no longer applies — sending again, or a successful retry, should clear it.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// struct ConversationView: View {
    ///     @State private var chat = Chat()
    ///     @State private var lastError: (any Error)?
    ///
    ///     var body: some View {
    ///         ChatView($chat)
    ///             .chatError(lastError) {
    ///                 lastError = nil
    ///                 respond()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - error: The failure to report, or `nil` when there is nothing to report.
    ///   - retry: Runs when the user asks to try again. Omit to report the failure without offering a retry.
    public func chatError(_ error: (any Error)?, retry: (@MainActor @Sendable () -> Void)? = nil) -> some View {
        environment(\.chatErrorState, ChatErrorState(error: error, retry: retry))
    }

    /// Reports a failure only while there is one, leaving any already in the environment alone otherwise.
    ///
    /// A view that wraps a chat and reports the failures of one particular thing — `LLMChatView` and its session,
    /// say — would otherwise clear whatever its host had set, just by being in between.
    ///
    /// - Parameters:
    ///   - error: The failure to show.
    ///   - retry: What to run when the user asks to try again. Pass `nil` for a failure that retrying cannot fix,
    ///     and no retry is offered.
    ///   - whileFailing: Whether to claim the environment at all.
    public func chatError(
        _ error: (any Error)?,
        retry: (@MainActor @Sendable () -> Void)? = nil,
        whileFailing: Bool
    ) -> some View {
        // `transformEnvironment` rather than an `if`: a conditional modifier would change this view's type as the
        // failure comes and goes, and SwiftUI would rebuild the whole conversation under it — losing the scroll
        // position and the half-typed message with it.
        transformEnvironment(\.chatErrorState) { state in
            guard whileFailing else {
                return
            }
            state = ChatErrorState(error: error, retry: retry)
        }
    }
}
