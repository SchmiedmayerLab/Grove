//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// What a chat has said about the answer it is producing.
///
/// Absent from the environment until a chat reports it, which is how the typing indicator can tell "not
/// generating" from "never said" and fall back to its own guess only in the latter case.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatGeneration {
    /// Whether a response is being produced right now.
    var isGenerating = false
    /// A stopped or failed answer requires the participant to resume the waiting messages.
    var queuePaused = false
    /// Stops the response in flight, when the chat offers that.
    var cancel: (@MainActor () -> Void)?
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// What the chat has said about the answer it is producing, or `nil` if it has said nothing.
    @Entry var chatGeneration: ChatGeneration?
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Tells the chat that the assistant is answering.
    ///
    /// While generating, new messages wait in the composer's queue. Supply `onCancel` to offer a stop button;
    /// stopping also pauses the queue until the participant resumes it. Set `queuePaused` when an answer fails
    /// or is cancelled outside the composer, so the remaining messages wait for the same explicit choice.
    ///
    /// The typing indicator follows this too, so a chat that reports its generation state does not also need
    /// `messagePendingAnimation`.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatGenerating(llm.state == .generating) {
    ///         llm.cancel()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - isGenerating: Whether a response is being produced right now.
    ///   - queuePaused: Whether the latest answer failed or was cancelled. A transition to `true` pauses automatic
    ///                  sending; the participant can still resume the queue while the error is displayed.
    ///   - onCancel: Stops the response in flight. Omit if the chat cannot be interrupted.
    public func chatGenerating(
        _ isGenerating: Bool,
        queuePaused: Bool = false,
        onCancel: (@MainActor () -> Void)? = nil
    ) -> some View {
        environment(\.chatGeneration, ChatGeneration(isGenerating: isGenerating, queuePaused: queuePaused, cancel: onCancel))
    }
}
