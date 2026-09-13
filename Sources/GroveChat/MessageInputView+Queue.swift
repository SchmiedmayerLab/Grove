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
    /// What is waiting for the answer in flight, stacked above the field on glass; the stack itself leaves while
    /// it is fanned out over the conversation.
    @ViewBuilder var queuedMessages: some View {
        if !queue.isExpanded {
            QueuedMessageStack(
                messages: queue.messages,
                cornerRadius: Self.cornerRadius,
                edit: edit,
                fanOut: { queue.isExpanded = true },
                removeAll: { queue.messages.removeAll() }
            ) { chip in
                chip.glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// The attach button, which turns into the way out of the fanned-out queue for as long as that is open.
    @ViewBuilder var leadingAction: some View {
        if queue.isExpanded {
            closeButton(Text("HIDE_QUEUED_MESSAGES", bundle: .module)) {
                queue.isExpanded = false
            }
        } else {
            attachButton
        }
    }
}
