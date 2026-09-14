//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The queue as a dense stack: the next message in front, the edges of those behind it showing above, the way
/// cards sit in a wallet, so that a glance says there is more than one.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QueuedMessageStack<Front: View>: View {
    private static var peeks: Int { 2 }
    private static var peekOffset: CGFloat { 5 }

    let messages: [QueuedMessage]
    let cornerRadius: CGFloat
    let edit: (QueuedMessage) -> Void
    let fanOut: () -> Void
    /// Drops the whole queue.
    let removeAll: () -> Void
    /// The card in front on the surface the composer gives it.
    @ViewBuilder let front: (QueuedMessageChip) -> Front

    var body: some View {
        if let next = messages.first {
            front(QueuedMessageChip(message: next, count: messages.count, edit: { edit(next) }, fanOut: fanOut, remove: removeAll))
                // The cards behind, sized by the one in front: only their upper edges show.
                .background {
                    ForEach(1..<min(messages.count, Self.peeks + 1), id: \.self) { depth in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .strokeBorder(.quaternary, lineWidth: 0.5)
                            }
                            .scaleEffect(x: 1 - 0.04 * CGFloat(depth), y: 1, anchor: .center)
                            .offset(y: -Self.peekOffset * CGFloat(depth))
                            .zIndex(-Double(depth))
                    }
                }
                .padding(.top, Self.peekOffset * CGFloat(min(messages.count - 1, Self.peeks)))
        }
    }
}
