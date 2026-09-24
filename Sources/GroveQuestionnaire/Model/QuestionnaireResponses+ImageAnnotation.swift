//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
#if canImport(PencilKit)
public import PencilKit
#endif
#if canImport(UIKit)
public import class UIKit.UIImage
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// An annotation collected by asking the user to draw onto an image.
    public struct ImageAnnotation: CustomResponseValueProtocol, Hashable, Sendable {
        /// The drawing, in PencilKit's own serialization.
        ///
        /// Held as bytes rather than a `PKDrawing` so a collected annotation survives storage and
        /// transfer wherever a response travels, including platforms without PencilKit. An annotation
        /// carrying no strokes is empty data, which keeps ``isEmpty`` answerable off-Apple.
        public var drawingData: Data

        /// Whether the annotation is empty.
        public var isEmpty: Bool {
            drawingData.isEmpty
        }

        /// Creates an empty annotation.
        public init() {
            self.drawingData = Data()
        }

        /// Creates an annotation from PencilKit's serialized drawing representation.
        public init(drawingData: Data) {
            self.drawingData = drawingData
        }
    }
}


#if canImport(PencilKit)
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.ImageAnnotation {
    /// The annotation as a PencilKit drawing.
    ///
    /// Reading an annotation whose bytes PencilKit cannot decode yields an empty drawing rather than
    /// throwing: a response that arrived from another platform must not take the editor down with it.
    public var drawing: PKDrawing {
        get { (try? PKDrawing(data: drawingData)) ?? PKDrawing() }
        set { drawingData = newValue.strokes.isEmpty ? Data() : newValue.dataRepresentation() }
    }

    /// Creates an annotation from a PencilKit drawing.
    public init(drawing: PKDrawing) {
        self.init()
        self.drawing = drawing
    }
}
#endif


#if canImport(UIKit)
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.ImageAnnotation {
    /// Produces an image by overlaying the drawing onto a base image.
    public func draw(onto baseImage: UIImage) -> UIImage? {
        let pixelSize = baseImage.size.applying(
            CGAffineTransform(scaleX: baseImage.scale, y: baseImage.scale)
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }
        let drawing = self.drawing
        // The editor stores PencilKit coordinates in source-image pixels. Rendering at a
        // scale of one preserves those coordinates for both @1x and Retina base images.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: pixelSize))
            guard !drawing.bounds.isEmpty else {
                return
            }
            drawing.image(from: drawing.bounds, scale: 1).draw(in: drawing.bounds)
        }
        guard let renderedCGImage = rendered.cgImage else {
            return nil
        }
        return UIImage(cgImage: renderedCGImage, scale: baseImage.scale, orientation: .up)
    }
}
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.Response.Value {
    // swiftlint:disable:next missing_docs
    public var annotatedImageValue: QuestionnaireResponses.ImageAnnotation? {
        get { self[asCustomTypeA: QuestionnaireResponses.ImageAnnotation.self] }
        set { self[asCustomTypeA: QuestionnaireResponses.ImageAnnotation.self] = newValue }
    }
}
