//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import QuickLookThumbnailing
import SwiftUI


/// An `Image` displaying a thumbnail for a file ata `URL`.
struct FileThumbnail: View {
    @Environment(\.displayScale) private var scale
    private let url: URL
    private let size: CGSize
    private let representationTypes: QLThumbnailGenerator.Request.RepresentationTypes
    // CGImage rather than UIImage, so that the view works on both UIKit and AppKit platforms.
    @State private var image: CGImage?

    var body: some View {
        VStack {
            if let image {
                Image(decorative: image, scale: scale)
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: representationTypes
            )
            let generator = QLThumbnailGenerator.shared
            guard let thumbnail = try? await generator.generateBestRepresentation(for: request) else {
                return
            }
            self.image = thumbnail.cgImage
        }
    }

    init(
        url: URL,
        size: CGSize = CGSize(width: 50, height: 50),
        representationTypes: QLThumbnailGenerator.Request.RepresentationTypes = .all
    ) {
        self.url = url
        self.size = size
        self.representationTypes = representationTypes
    }
}
