//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Styles a ``ChatEntity``'s content as a chat bubble within the ``ChatView``.
///
/// Only messages that sit on the trailing edge — the user's own — get a bubble; assistant output runs
/// full-width against the view's background, matching how modern assistant UIs read.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MessageStyleModifier: ViewModifier {
    /// The bubble's inset, which content that fills it edge to edge — an image — has to cancel out.
    static let padding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    static let cornerRadius: CGFloat = 22

    private let chatAlignment: ChatEntity.Alignment
    private let backgroundColorUserChat: Color?

    @Environment(\.chatAccentColor) private var chatAccentColor
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ChatPalette {
        ChatPalette(accent: chatAccentColor, colorScheme: colorScheme)
    }

    init(chatAlignment: ChatEntity.Alignment, backgroundColorUserChat: Color?) {
        self.chatAlignment = chatAlignment
        self.backgroundColorUserChat = backgroundColorUserChat
    }

    func body(content: Content) -> some View {
        switch chatAlignment {
        case .leading:
            content
                .foregroundStyle(.primary)
        case .trailing:
            content
                .padding(Self.padding)
                .foregroundStyle(palette.userBubbleLabel)
                .background(
                    backgroundColorUserChat ?? palette.userBubble,
                    in: .rect(cornerRadius: Self.cornerRadius, style: .continuous)
                )
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Formats content as a chat bubble within a chat view.
    ///
    /// The modifier handles padding, colouring, and the bubble background.
    ///
    /// As visionOS doesn't properly resolve the `.accentColor` during chat export via the `ImageRenderer`
    /// — it was always "white" in our testing — a custom background color can be passed for user messages.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// struct ChatMessageView: View {
    ///     let chatEntity: ChatEntity
    ///
    ///     var body: some View {
    ///         Text(chatEntity.content.text ?? "")
    ///             .chatMessageStyle(alignment: chatEntity.alignment)
    ///     }
    /// }
    /// ```
    @available(iOS 18, macOS 15, watchOS 11, *)
    func chatMessageStyle(alignment: ChatEntity.Alignment, backgroundColorUserChat: Color? = nil) -> some View {
        modifier(MessageStyleModifier(chatAlignment: alignment, backgroundColorUserChat: backgroundColorUserChat))
    }
}
