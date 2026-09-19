//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveChat
import Testing


@Suite("Queued message reordering")
struct QueuedMessageReorderTests {
    @Test("A drag can move away and return to its starting row")
    func reversesWithinOneGesture() {
        var messages = ["First", "Second", "Third"].map { QueuedMessage(text: $0, quotation: nil, attachments: []) }
        let originalOrder = messages.map(\.id)
        var drag = QueuedMessageReorder(id: messages[0].id, origin: 0)

        #expect(drag.update(translation: 64, rowHeight: 64, messages: &messages))
        #expect(messages.map(\.text) == ["Second", "First", "Third"])
        #expect(!drag.update(translation: 70, rowHeight: 64, messages: &messages), "Staying in one row does not repeat the move or its haptic")
        #expect(messages.map(\.text) == ["Second", "First", "Third"])
        #expect(drag.offset == 6)
        #expect(drag.update(translation: 0, rowHeight: 64, messages: &messages))
        #expect(messages.map(\.id) == originalOrder)
        #expect(drag.offset == 0)
    }

    @Test("Dragging past the last row clamps once and can still return")
    func clampsAtQueueBoundary() {
        var messages = ["First", "Second", "Third"].map { QueuedMessage(text: $0, quotation: nil, attachments: []) }
        var drag = QueuedMessageReorder(id: messages[1].id, origin: 1)

        #expect(drag.update(translation: 256, rowHeight: 64, messages: &messages))
        #expect(messages.map(\.text) == ["First", "Third", "Second"])
        #expect(!drag.update(translation: 300, rowHeight: 64, messages: &messages))
        #expect(drag.update(translation: -64, rowHeight: 64, messages: &messages))
        #expect(messages.map(\.text) == ["Second", "First", "Third"])
    }
}
