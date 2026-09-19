//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


private struct DismissChatKeyboardKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}


extension EnvironmentValues {
    /// Dismisses this chat's composer before an attachment viewer opens.
    /// A standalone message view has no composer and leaves other text fields alone.
    var dismissChatKeyboard: @MainActor () -> Void {
        get { self[DismissChatKeyboardKey.self] }
        set { self[DismissChatKeyboardKey.self] = newValue }
    }
}
