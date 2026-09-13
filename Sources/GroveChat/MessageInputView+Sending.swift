//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    func send() {
        guard canSend else {
            return
        }
        speechRecognizer.stop()
        let draft = QueuedMessage(
            text: message.trimmingCharacters(in: .whitespacesAndNewlines),
            quotation: quotation,
            attachments: attachments
        )
        message = ""
        quotation = nil
        attachments = []
        #if canImport(PhotosUI)
        photoSelection = []
        #endif
        if isGenerating {
            queue.messages.append(draft)
        } else {
            chat.append(draft.entity)
        }
    }

    /// Lets the first queued message go, once the chat can take it.
    ///
    /// One at a time: the next waits for the answer this one gets. A composer that has been closed in the meantime
    /// keeps them, as it keeps anything else the participant has staged.
    func sendNextQueued() {
        guard isEnabled, !queue.messages.isEmpty else {
            return
        }
        chat.append(queue.messages.removeFirst().entity)
    }

    /// Takes a queued message back into the field, ahead of whatever is being written there.
    func edit(_ queuedMessage: QueuedMessage) {
        queue.messages.removeAll { $0.id == queuedMessage.id }
        message = [queuedMessage.text, message].filter { !$0.isEmpty }.joined(separator: "\n")
        quotation = queuedMessage.quotation ?? quotation
        attachments = queuedMessage.attachments + attachments
        textFieldIsFocused = true
    }
}
