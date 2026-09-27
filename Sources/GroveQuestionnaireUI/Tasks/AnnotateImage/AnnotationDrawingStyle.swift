//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
import PencilKit
import UIKit


@available(iOS 18, macOS 15, watchOS 11, *)
enum AnnotationDrawingStyle {
    private static let lineWidthRatio = 0.014
    private static let lineWidthRange: ClosedRange<CGFloat> = 6...72
    private static let eraserWidthMultiplier = CGFloat(2)

    static func tool(for region: AnnotateImageConfig.Region, image: UIImage) -> PKInkingTool {
        PKInkingTool(
            ink: AnnotateImageView.ink(for: region),
            width: lineWidth(for: image)
        )
    }

    /// Twice the stroke width: a pass along a mark clears it, a pass across only trims it.
    static func eraser(for image: UIImage) -> PKEraserTool {
        PKEraserTool(.bitmap, width: lineWidth(for: image) * eraserWidthMultiplier)
    }

    static func lineWidth(for image: UIImage) -> CGFloat {
        let pixelWidth = image.size.width * image.scale
        return min(max(pixelWidth * lineWidthRatio, lineWidthRange.lowerBound), lineWidthRange.upperBound)
    }
}
#endif
