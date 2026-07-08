//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


private struct AsyncButtonProcessingStyleKey: EnvironmentKey {
    static let defaultValue: AsyncButtonProcessingStyle = .overlay
}


/// Define how an `AsyncButton` visualizes it's processing state.
public enum AsyncButtonProcessingStyle: Hashable, Sendable {
    /// Draw a `ProgressView` as an overlay replacing the button view.
    case overlay
    /// Draw a `ProgressView` next to the button label.
    case listRow
}


extension EnvironmentValues {
    var asyncButtonProcessingStyle: AsyncButtonProcessingStyle {
        get {
            self[AsyncButtonProcessingStyleKey.self]
        }
        set {
            self[AsyncButtonProcessingStyleKey.self] = newValue
        }
    }
}


extension View {
    /// Define how an `AsyncButton` visualizes it's processing state.
    /// - Parameter style: The processing style.
    /// - Returns: Returns the modified view.
    public func asyncButtonProcessingStyle(_ style: AsyncButtonProcessingStyle) -> some View {
        environment(\.asyncButtonProcessingStyle, style)
    }
}
