//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Whether something inside a container still blocks the page; the container paints the tint in its own shape.
private struct BlockingPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}


private struct HighlightsBlockingContent<HighlightShape: Shape>: ViewModifier {
    let shape: HighlightShape

    @State private var isBlocking = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(BlockingPreferenceKey.self) { isBlocking = $0 }
            .blockingHighlight(isBlocking, in: shape)
    }
}


private struct ReportsBlocking: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isBlocking: Bool

    func body(content: Content) -> some View {
        content
            .preference(key: BlockingPreferenceKey.self, value: isBlocking)
            // A form row has no container of ours, so the row itself takes the tint; `nil` hands the row back to the list.
            .listRowBackground(isBlocking ? Color.blockingTint(for: colorScheme) : nil)
    }
}


extension View {
    /// Tells the enclosing container that this content still blocks the page.
    ///
    /// A ``SwiftUICore/View/highlightsBlockingContent(in:)`` container paints the tint in its own shape; a plain list row
    /// paints it over the whole row. The content itself stays untouched, so the mark always matches what holds it.
    public func reportsBlocking(_ isBlocking: Bool) -> some View {
        modifier(ReportsBlocking(isBlocking: isBlocking))
    }

    /// Paints the blocking tint in `shape` whenever content inside ``SwiftUICore/View/reportsBlocking(_:)`` a problem.
    public func highlightsBlockingContent(in shape: some Shape = .rect) -> some View {
        modifier(HighlightsBlockingContent(shape: shape))
    }
}
