//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotationEraserButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "eraser.fill" : "eraser")
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyleGlass(fallback: .bordered)
        .tint(isSelected ? Color.accentColor : Color.secondary)
        .accessibilityLabel(Text("Eraser", bundle: .module))
        .accessibilityIdentifier("AnnotationEraser")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
