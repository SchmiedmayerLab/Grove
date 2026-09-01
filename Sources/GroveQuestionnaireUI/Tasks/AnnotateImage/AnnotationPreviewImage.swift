//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import PencilKit
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct AnnotationPreviewImage: View {
    let image: UIImage
    @Binding var drawing: PKDrawing

    var body: some View {
        ImageAnnotationView(image: image, drawing: $drawing, tool: .init(.pen))
            .accessibilityLabel(Text("Image", bundle: .module))
            .frame(height: 100)
            .disabled(true)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .accessibilityHidden(true)
                    .font(.caption.bold())
                    .padding(6)
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: Circle())
                    .padding(4)
            }
    }
}
#endif
