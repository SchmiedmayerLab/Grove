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
    /// While generating, the composer will not send a second message — a chat that accepts one mid-answer either
    /// interleaves two responses or silently drops the first. Supply `onCancel` and the send button becomes a stop
    /// button for as long as the answer is in flight; without it the button is simply unavailable.
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
    ///   - onCancel: Stops the response in flight. Omit if the chat cannot be interrupted.
    public func chatGenerating(_ isGenerating: Bool, onCancel: (@MainActor () -> Void)? = nil) -> some View {
        environment(\.chatGeneration, ChatGeneration(isGenerating: isGenerating, cancel: onCancel))
    }
}
