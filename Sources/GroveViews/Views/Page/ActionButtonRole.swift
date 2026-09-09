//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// The weight a button carries among a page's actions.
public enum ActionButtonRole {
    /// The page's main way forward, drawn in the accent color.
    case primary
    /// An alternative next to the primary action, such as skipping or postponing.
    case secondary
}


extension View {
    /// Styles a button the way ``PageActions`` styles its own, for a button that lives elsewhere on the page.
    ///
    /// Glass where the platform has it, bordered where it does not. Pair it with `.controlSize(.large)` and a
    /// full-width label to match.
    @ViewBuilder
    public func actionButtonStyle(_ role: ActionButtonRole) -> some View {
        #if os(visionOS)
        switch role {
        case .primary: buttonStyle(.borderedProminent)
        case .secondary: buttonStyle(.bordered)
        }
        #else
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            switch role {
            case .primary: buttonStyle(.glassProminent)
            case .secondary: buttonStyle(.glass)
            }
        } else {
            switch role {
            case .primary: buttonStyle(.borderedProminent)
            case .secondary: buttonStyle(.bordered)
            }
        }
        #endif
    }
}
