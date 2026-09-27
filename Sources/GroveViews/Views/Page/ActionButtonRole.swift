//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// The weight a button carries among a page's actions.
public enum ActionButtonRole: Sendable {
    /// The page's main way forward, drawn in the accent color.
    case primary
    /// An alternative next to the primary action, such as skipping or postponing.
    case secondary
}


extension EnvironmentValues {
    @Entry var disabledActionButtons: Set<ActionButtonRole> = []
}


extension View {
    /// Disables one of a ``PageActions``' buttons while the other stays live, for a page that keeps a way out open
    /// while its main action waits on something. `disabled(_:)` still covers both at once.
    public func actionButtonDisabled(_ role: ActionButtonRole, _ isDisabled: Bool = true) -> some View {
        transformEnvironment(\.disabledActionButtons) { roles in
            if isDisabled {
                roles.insert(role)
            } else {
                roles.remove(role)
            }
        }
    }

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
