//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A compact answer that opens something on tap: the value once there is one, the placeholder until then.
///
/// One shape for every such answer on a card, so a date, a drop-down and a file picker all read as the same
/// kind of control. Put it in the label of the button or menu that opens the answer.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AnswerPill: View {
    let text: Text
    let isPlaceholder: Bool
    /// A symbol after the text, for a control that opens a list rather than a picker.
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            text
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isPlaceholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
