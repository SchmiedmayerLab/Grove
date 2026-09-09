//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


private struct BlockingHighlight<HighlightShape: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isBlocking: Bool
    let shape: HighlightShape

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(isBlocking ? Color.blockingTint(for: colorScheme) : .clear)
            }
            .animation(.easeInOut(duration: 0.25), value: isBlocking)
    }
}


extension Color {
    /// The tint that marks a control while it is what keeps a page from continuing.
    ///
    /// A dark surface takes more of it than a white one before it reads as marked at all.
    public static func blockingTint(for colorScheme: ColorScheme) -> Color {
        .red.opacity(colorScheme == .dark ? 0.22 : 0.1)
    }
}


extension Animation {
    /// Brings a control the page has to return to back into view: short enough that the mark and the page read as one movement.
    public static var revisit: Animation {
        .snappy(duration: 0.25)
    }
}


extension View {
    /// Marks a control while it is what keeps a page from continuing.
    ///
    /// The mark stays for as long as the control is unanswered rather than flashing once, because the participant has
    /// to be able to find it again after scrolling past it.
    ///
    /// - Parameters:
    ///   - isBlocking: Whether the control currently keeps the page from continuing.
    ///   - shape: The shape the tint fills, matching the control's own background.
    public func blockingHighlight(_ isBlocking: Bool, in shape: some Shape = .rect) -> some View {
        modifier(BlockingHighlight(isBlocking: isBlocking, shape: shape))
    }
}
