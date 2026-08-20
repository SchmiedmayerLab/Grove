//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// The messages the chat keeps out of the conversation, whatever role they carry.
    @Entry var chatHiddenMessages: Set<UUID> = []
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Hides the identified messages from the chat, whatever role they carry.
    ///
    /// A chat that primes a model with input the participant never wrote — a synthetic opening turn, say —
    /// needs that input in the ``Chat`` it sends and out of the conversation the participant reads. Naming it
    /// here keeps the ``Chat`` a faithful record of the exchange, instead of asking the caller to maintain a
    /// second, re-roled copy of it.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatHiddenMessages([openingTurn.id])
    /// ```
    ///
    /// - Parameter ids: The identifiers of the messages to hide.
    public func chatHiddenMessages(_ ids: Set<UUID>) -> some View {
        environment(\.chatHiddenMessages, ids)
    }
}
