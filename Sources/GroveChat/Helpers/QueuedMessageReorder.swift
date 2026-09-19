//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Keeps the gesture's starting row stable while the view redraws the reordered cards.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QueuedMessageReorder {
    let id: UUID
    let origin: Int
    private(set) var offset: CGFloat = 0

    /// Returns whether the card crossed into a different row, for one haptic per move.
    mutating func update(translation: CGFloat, rowHeight: CGFloat, messages: inout [QueuedMessage]) -> Bool {
        guard let current = messages.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let rows = Int((translation / rowHeight).rounded())
        let target = min(max(origin + rows, 0), messages.count - 1)
        offset = translation - CGFloat(target - origin) * rowHeight
        guard target != current else {
            return false
        }
        messages.move(fromOffsets: IndexSet(integer: current), toOffset: target > current ? target + 1 : target)
        return true
    }
}
