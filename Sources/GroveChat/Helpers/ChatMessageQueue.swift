//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//
import SwiftUI


/// The messages written while an answer was arriving, shared between the composer that holds them and the
/// conversation they fan out over.
///
/// The composer owns the field; the fan-out lives above it, over the messages. Both read and write the same
/// queue here, the way a quotation travels through ``ChatFollowUp``.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
@MainActor
final class ChatMessageQueue {
    var messages: [QueuedMessage] = []
    /// Whether the queue is fanned out over the conversation.
    var isExpanded = false
    /// A message the fan-out handed back for editing, for the composer to take into its field.
    var messageToEdit: QueuedMessage?

    func remove(_ message: QueuedMessage) {
        messages.removeAll { $0.id == message.id }
        if messages.isEmpty {
            isExpanded = false
        }
    }

    func edit(_ message: QueuedMessage) {
        isExpanded = false
        messageToEdit = message
    }
}
