//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveChat
import Testing


@Suite("Following streamed chat content")
@MainActor
struct StreamingScrollTests {
    @Test("An image placeholder and its replacement count as streaming")
    func followsGeneratedImage() {
        let user = ChatEntity(role: .user, text: "Draw a picture")
        let placeholder = ChatEntity(role: .assistant(.response), content: .image(.generating))
        let image = ChatEntity(
            role: .assistant(.response),
            content: .image(.url(URL(fileURLWithPath: "/picture.png"))),
            id: placeholder.id
        )

        #expect(placeholder.complete)
        #expect(MessagesView.answerIsStreaming(from: [user], to: [user, placeholder]))
        #expect(MessagesView.answerIsStreaming(from: [user, placeholder], to: [user, image]))
        #expect(!MessagesView.answerIsStreaming(from: [user], to: [user, image]), "An image that arrives whole keeps the reader's position")
    }

    @Test("Finished text edits do not restart following, but the final streamed text does")
    func preservesTextBehavior() {
        let partial = ChatEntity(role: .assistant(.response), text: "First", complete: false)
        let final = ChatEntity(role: .assistant(.response), text: "First answer", id: partial.id)
        let edited = ChatEntity(role: .assistant(.response), text: "First answer with a citation", id: partial.id)

        #expect(MessagesView.answerIsStreaming(from: [], to: [partial]))
        #expect(MessagesView.answerIsStreaming(from: [partial], to: [final]))
        #expect(!MessagesView.answerIsStreaming(from: [final], to: [edited]))
    }
}
