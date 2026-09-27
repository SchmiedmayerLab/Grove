//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
@testable import GroveChat
import SnapshotTesting
import SwiftUI
import Testing


@available(iOS 26, *)
private struct ComposerHost: View {
    @State private var chat: Chat = []
    @State private var queue: ChatMessageQueue
    @FocusState private var isFocused: Bool

    var body: some View {
        MessageInputView($chat, isFocused: $isFocused)
            .environment(queue)
            .chatAttachments(.all)
            .background(Color.white)
    }

    init(queueIsExpanded: Bool) {
        let queue = ChatMessageQueue()
        queue.isExpanded = queueIsExpanded
        _queue = State(initialValue: queue)
    }
}


/// Pins the composer at rest and with the queue fanned out: a button style that pads its label grows the round controls
/// past the field, which only a picture of the whole row shows.
@Suite("Composer Snapshots")
@MainActor
struct ComposerSnapshotTests {
    @Test("The attach and microphone buttons are as tall as the field")
    func atRest() {
        guard #available(iOS 26, *) else {
            return
        }
        assertSnapshot(of: ComposerHost(queueIsExpanded: false), as: .image(layout: .fixed(width: 402, height: 72)), named: "at-rest")
    }

    @Test("The button that closes the queue is as tall as the field")
    func queueFannedOut() {
        guard #available(iOS 26, *) else {
            return
        }
        assertSnapshot(of: ComposerHost(queueIsExpanded: true), as: .image(layout: .fixed(width: 402, height: 72)), named: "queue-fanned-out")
    }
}
#endif
