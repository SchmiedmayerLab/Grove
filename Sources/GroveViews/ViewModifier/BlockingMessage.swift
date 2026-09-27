//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Says what keeps a page from continuing, under the control it is about.
///
/// Questionnaires put it under an unanswered question, consent forms under a missing choice or signature, and
/// validated text fields under input that fails a rule; together with ``SwiftUICore/View/blockingHighlight(_:in:)``
/// it is the one signal a participant learns for "this still needs you".
public struct BlockingMessage: View {
    private let message: Text

    @_documentation(visibility: internal)
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
            message
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// - Parameter message: What is missing or wrong, in a few words.
    public init(_ message: Text) {
        self.message = message
    }
}
