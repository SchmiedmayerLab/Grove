//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveChat
import Testing


@Suite("Chat queue pause and resume")
@MainActor
struct ChatMessageQueueTests {
    @Test("A stopped or failed answer holds every queued message until resumed")
    func holdsUntilResumed() {
        let queue = ChatMessageQueue()
        queue.messages = ["First", "Second"].map { QueuedMessage(text: $0, quotation: nil, attachments: []) }
        queue.pause()

        #expect(queue.takeNext() == nil)
        #expect(queue.messages.map(\.text) == ["First", "Second"])
        queue.resume()
        #expect(queue.takeNext()?.text == "First")
        #expect(queue.messages.map(\.text) == ["Second"])
    }

    @Test("Sending the last queued message also closes its expanded view")
    func closesWhenDrained() {
        let queue = ChatMessageQueue()
        queue.messages = [QueuedMessage(text: "Last", quotation: nil, attachments: [])]
        queue.isExpanded = true

        #expect(queue.takeNext()?.text == "Last")
        #expect(queue.messages.isEmpty)
        #expect(!queue.isExpanded)
    }
}
