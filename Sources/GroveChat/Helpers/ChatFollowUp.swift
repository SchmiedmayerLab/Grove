//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The quoted text a composer is holding for the next message, shown above the field until it is sent.
///
/// Kept apart from what the participant types, the way a picked photo is: the two are only joined when
/// the message goes, so the participant edits their own words without the quotation in the way.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuotationChip: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("REMOVE_QUOTATION", bundle: .module))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .combine)
    }
}


/// Stages a quoted message in the composer as it arrives.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuotationPickup: ViewModifier {
    @Binding var quotation: String?
    var isFocused: FocusState<Bool>.Binding

    @Environment(ChatFollowUp.self) private var followUp: ChatFollowUp?

    func body(content: Content) -> some View {
        content.onChange(of: followUp?.pendingQuotation) { _, pending in
            guard let pending else {
                return
            }
            withAnimation(.smooth(duration: 0.25)) {
                quotation = pending
            }
            followUp?.pendingQuotation = nil
            isFocused.wrappedValue = true
        }
    }
}


/// Carries a quoted message from the conversation down to the composer.
///
/// The composer owns the text the participant is writing, and the messages above it have no way to reach that
/// text on their own. This sits in the environment of both, so asking about a message puts it in the field
/// instead of making the participant retype what they are asking about.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
final class ChatFollowUp {
    /// The quotation waiting to be placed in the composer, if any.
    var pendingQuotation: String?

    /// Quotes the given text for the composer to pick up.
    ///
    /// Blank text is ignored: a quotation of nothing would only push the participant's own words down the field.
    func quote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        pendingQuotation = trimmed
    }
}


extension String {
    /// The text as a Markdown block quote, one `>` per line so a multi-line passage stays one quote.
    var markdownQuoted: String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }

    /// The message to send: the quotation first, then whatever the participant wrote, a blank line apart.
    ///
    /// A block quote is what the model reads and what the bubble renders, so the one encoding serves both.
    static func message(quoting quotation: String?, text: String) -> String {
        [quotation?.markdownQuoted, text.isEmpty ? nil : text]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}
