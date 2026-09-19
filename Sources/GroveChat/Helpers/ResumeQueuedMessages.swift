//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct ResumeQueuedMessages: View {
    let queue: ChatMessageQueue
    let isGenerating: Bool
    let resume: () -> Void

    var body: some View {
        if queue.isPaused, !queue.messages.isEmpty {
            Button(action: resume) {
                Label {
                    Text("RESUME_QUEUED_MESSAGES", bundle: .module)
                } icon: {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .disabled(isGenerating)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
