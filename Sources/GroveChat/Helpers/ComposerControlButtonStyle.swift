//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A round control beside the composer's field, on glass and exactly as tall as the field.
///
/// The system glass button style pads its label, which made these circles outgrow the field; the glass sits inside
/// the button here, as it does in that style, so a tap still reaches the button's action.
@available(iOS 26, macOS 26, visionOS 26, *)
struct ComposerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: MessageInputView.controlSize, height: MessageInputView.controlSize)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}


@available(iOS 26, macOS 26, visionOS 26, *)
extension ButtonStyle where Self == ComposerControlButtonStyle {
    /// A round control beside the composer's field, exactly as tall as the field.
    static var composerControl: ComposerControlButtonStyle {
        ComposerControlButtonStyle()
    }
}
