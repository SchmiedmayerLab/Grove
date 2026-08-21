//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// The colors the chat uses, derived from the app's accent color.
///
/// Controls carry the accent as the app set it. The conversation does not: a message's fill folds the accent
/// into a gray, so a chat picks up the app's identity without turning into a block of brand color.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatPalette {
    /// The accent used for the chat's controls — the send button, most visibly.
    ///
    /// Carried at full strength, unlike ``userBubble``: the send button is the one place a chat should look
    /// like the app it lives in.
    let accent: Color
    /// The color that reads on top of ``accent``.
    let onAccent: Color
    /// The fill behind a message the user sent.
    let userBubble: Color

    /// The color that reads on top of ``userBubble``.
    ///
    /// The bubble stays close enough to the surrounding background for the ordinary label color to carry it.
    var userBubbleLabel: Color {
        .primary
    }

    init(accent: Color, colorScheme: ColorScheme) {
        self.accent = accent
        // White on a filled accent, the way a tinted control reads everywhere else in the system.
        self.onAccent = .white
        switch colorScheme {
        case .dark:
            // A darker bubble swallows the tint, so dark mode takes more of the accent than light mode to land
            // at the same perceived amount of colour.
            self.userBubble = Color(white: 0.24).mix(with: accent, by: 0.2)
        default:
            self.userBubble = Color(white: 0.92).mix(with: accent, by: 0.10)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// The color the chat derives its palette from. Defaults to the app's accent color.
    @Entry var chatAccentColor: Color = .accentColor
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Sets the color the chat derives its palette from.
    ///
    /// The chat greys the color down before using it, so a saturated accent still reads as a tint rather than as a
    /// block of brand color. Leave this unset to follow the app's accent color.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatAccentColor(.indigo)
    /// ```
    public func chatAccentColor(_ color: Color) -> some View {
        environment(\.chatAccentColor, color)
    }
}
