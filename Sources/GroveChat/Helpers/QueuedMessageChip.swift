//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A message written while an answer was still arriving, held by the composer until that answer is in.
///
/// Sending it straight away would either interleave two answers or drop the one in flight, and refusing it would
/// make the participant wait with their thought half typed. So the composer keeps it, shows it above the field,
/// and lets it go the moment the chat is free.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    let quotation: String?
    let attachments: [DraftAttachment]

    /// What the chip shows: the participant's words, else the quotation, else the pictures and files alone.
    var preview: Text {
        if !text.isEmpty {
            Text(text)
        } else if let quotation {
            Text(quotation)
        } else {
            Text("ATTACHMENTS_ONLY_MESSAGE \(attachments.count)", bundle: .module)
        }
    }

    /// The message as it goes into the chat.
    var entity: ChatEntity {
        var parts = attachments.map { attachment in
            switch attachment.content {
            case .image(let image): ChatEntity.Content.Part(.image(.image(image)))
            case .file(let file): ChatEntity.Content.Part(.file(file), label: file.name)
            }
        }
        let joined = String.message(quoting: quotation, text: text)
        if !joined.isEmpty {
            parts.append(ChatEntity.Content.Part(.text(joined)))
        }
        return ChatEntity(role: .user, content: ChatEntity.Content(parts))
    }
}


/// A queued message above the field: the next one to go, with a way to take it back into the field, or the top
/// of a stack of them, with a way to fan the stack out.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QueuedMessageChip: View {
    let message: QueuedMessage
    /// How many messages wait, this one included.
    let count: Int
    let edit: () -> Void
    let fanOut: () -> Void
    /// Drops this message, or the whole stack when it is the top of one.
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                    Text("QUEUED_MESSAGES \(count)", bundle: .module)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                message.preview
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if count > 1 {
                Button(action: fanOut) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("SHOW_QUEUED_MESSAGES", bundle: .module))
                }
                .buttonStyle(.plain)
                .symbolEffect(.bounce, value: count)
            } else {
                Button(action: edit) {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("EDIT_QUEUED_MESSAGE", bundle: .module))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onTapGesture {
            if count > 1 {
                fanOut()
            }
        }
        .contextMenu {
            if count > 1 {
                Button(action: fanOut) {
                    Label {
                        Text("SHOW_QUEUED_MESSAGES", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.stack")
                    }
                }
            } else {
                Button(action: edit) {
                    Label {
                        Text("EDIT_QUEUED_MESSAGE", bundle: .module)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }
            Button(role: .destructive, action: remove) {
                Label {
                    Text(count > 1 ? "REMOVE_QUEUED_MESSAGES" : "REMOVE_QUEUED_MESSAGE", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Queued Message")
    }
}
