//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveViews
public import PencilKit
#if canImport(UIKit)
public import class UIKit.UIImage
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// An annotation collected by asking the user to draw onto an image.
    public struct ImageAnnotation: CustomResponseValueProtocol, Hashable, Sendable {
        /// The actual drawing produced by the user.
        public var drawing: PKDrawing
        
        /// Whether the annotation is empty.
        public var isEmpty: Bool {
            drawing.isEmpty
        }
        
        /// Creates an empty annotation.
        public init() {
            self.init(drawing: PKDrawing())
        }
        
        /// Creates an annotation from a PencilKit drawing.
        public init(drawing: PKDrawing) {
            self.drawing = drawing
        }
        
        /// Produces an image by overlaying the drawing onto a base image.
#if canImport(UIKit)
        public func draw(onto baseImage: UIImage) -> UIImage? {
            let pixelSize = baseImage.size.applying(
                CGAffineTransform(scaleX: baseImage.scale, y: baseImage.scale)
            )
            guard pixelSize.width > 0, pixelSize.height > 0 else {
                return nil
            }

            // The editor stores PencilKit coordinates in source-image pixels. Rendering at a
            // scale of one preserves those coordinates for both @1x and Retina base images.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
                baseImage.draw(in: CGRect(origin: .zero, size: pixelSize))
                guard !drawing.isEmpty else {
                    return
                }
                drawing.image(from: drawing.bounds, scale: 1).draw(in: drawing.bounds)
            }
            guard let renderedCGImage = rendered.cgImage else {
                return nil
            }
            return UIImage(cgImage: renderedCGImage, scale: baseImage.scale, orientation: .up)
        }
        #endif
    }
}
