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
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.tertiary)
                    .opacity(isAnimating ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(0.2 * Double(index)),
                        value: isAnimating
                    )
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            isAnimating = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("TYPING_INDICATOR", bundle: .module))
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
