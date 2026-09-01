//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Something the renderer has to say about an answer, under the question it is about.
///
/// An `HStack` rather than a `Label`: inside a form a label indents its title to the column the
/// list reserves for icons, which left the message floating well clear of the question above it.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuestionMessage: View {
    private let message: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            message
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    init(_ message: Text) {
        self.message = message
    }
}
