//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if Textual
import Textual


/// Draws a block quote the way the composer showed it before it was sent.
///
/// A quoted passage is how a participant asks about part of an answer, and it should read as that in the
/// bubble too, not as a Markdown citation.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatQuoteStyle: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 3)
            configuration.label
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 3)
        }
    }
}
#endif
