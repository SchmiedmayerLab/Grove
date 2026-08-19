//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// What a ``ChatView`` shows in place of a conversation that hasn't started yet.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatEmptyState {
    /// The view to render, or `nil` to leave the space empty.
    let content: (@MainActor () -> AnyView)?
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// What to show while the chat has no visible messages.
    @Entry var chatEmptyState = ChatEmptyState(content: nil)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Shows a placeholder while the chat has no visible messages.
    ///
    /// An empty conversation is otherwise a blank sheet above the composer. Use this to say what the assistant is
    /// for, or to offer somewhere to start. The placeholder disappears as soon as the first message arrives.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatEmptyState(
    ///         "Ask About Your Medication",
    ///         description: "Answers come from your care team's guidance, not the open internet."
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - title: The headline of the placeholder.
    ///   - description: Supporting text below the title, if any.
    ///   - systemImage: The SF Symbol shown above the title. Pass `nil` for a text-only placeholder.
    public func chatEmptyState(
        _ title: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        systemImage: String? = "bubble.left.and.bubble.right"
    ) -> some View {
        chatEmptyState {
            ContentUnavailableView {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                }
            } description: {
                if let description {
                    Text(description)
                }
            }
        }
    }

    /// Shows a custom placeholder while the chat has no visible messages.
    ///
    /// Use this when the placeholder needs to do more than describe itself — offering starter prompts, say.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatEmptyState {
    ///         VStack(spacing: 12) {
    ///             Text("What would you like to know?")
    ///             ForEach(starters, id: \.self) { starter in
    ///                 Button(starter) { chat.append(ChatEntity(role: .user, text: starter)) }
    ///             }
    ///         }
    ///     }
    /// ```
    public func chatEmptyState(@ViewBuilder _ content: @escaping @MainActor () -> some View) -> some View {
        environment(\.chatEmptyState, ChatEmptyState(content: { AnyView(content()) }))
    }
}
