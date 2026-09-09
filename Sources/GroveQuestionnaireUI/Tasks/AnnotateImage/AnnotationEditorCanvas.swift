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
struct AnnotationEditorCanvas: View {
    let image: UIImage
    let selectedRegion: AnnotateImageConfig.Region?
    @Binding var drawing: PKDrawing
    let contentInsets: UIEdgeInsets
    let history: AnnotationHistoryController

    var body: some View {
        ZoomableImageAnnotationView(
            image: image,
            drawing: $drawing,
            tool: selectedRegion.map { AnnotationDrawingStyle.tool(for: $0, image: image) } ?? .init(.crayon),
            isDrawingEnabled: selectedRegion != nil,
            contentInsets: contentInsets,
            history: history
        )
        .background(Color(uiColor: .secondarySystemBackground))
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}
#endif
