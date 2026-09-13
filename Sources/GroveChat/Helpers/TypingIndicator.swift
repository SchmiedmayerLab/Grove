//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A typing indicator animation for pending messages.
///
/// Three dots fade in and out in a sequential, wave-like pattern, looping for as long as the view is on screen.
@available(iOS 18, macOS 15, watchOS 11, *)
struct TypingIndicator: View {
    /// One fade there and back, in seconds.
    private static let period: TimeInterval = 1.2
    /// How far each dot runs behind the one before it, in seconds.
    private static let stagger: TimeInterval = 0.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                dots(at: nil)
            } else {
                // Driven by the clock rather than by a repeating animation: an animation attached to each dot also
                // took hold of the dot's position, so a message arriving above scattered the dots as they moved down.
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    dots(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("TYPING_INDICATOR", bundle: .module))
    }

    private static func opacity(of index: Int, at time: TimeInterval) -> Double {
        let phase = (time - stagger * Double(index)) / period * 2 * .pi
        return 0.25 + 0.75 * (0.5 - 0.5 * cos(phase))
    }

    private func dots(at time: TimeInterval?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.tertiary)
                    .opacity(time.map { Self.opacity(of: index, at: $0) } ?? 0.6)
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    VStack(alignment: .leading) {
        PlainMessageView(ChatEntity(role: .assistant(.response), text: "Assistant Message!"))
        TypingIndicator()
    }
    .padding()
}
#endif
