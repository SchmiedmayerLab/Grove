//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// A message's bubble, with the tail Messages puts at the corner nearest whoever sent it.
///
/// One continuous outline rather than a rounded rectangle with a tail drawn over it: overlapping
/// subpaths seam wherever the fill is not fully opaque, and the chord that closed the overlaid tail
/// left a sliver of background showing between it and the bubble's corner.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatBubbleShape: Shape {
    /// How far the tail reaches past the body of the bubble.
    static let tailWidth: CGFloat = 4

    let cornerRadius: CGFloat
    /// Which side the tail leaves from, so it stays on the sender's side in a right-to-left layout.
    let tailEdge: HorizontalEdge
    /// Whether the bubble carries a tail at all; only the last message of a sender's run does.
    var drawsTail = true

    func path(in rect: CGRect) -> Path {
        // The body always fills the rect, so a run's bubbles share one trailing margin whether they
        // carry the tail or not; the tail overhangs the bounds into the margin, the way Messages draws it.
        let body = rect
        guard drawsTail else {
            return Path(roundedRect: body, cornerRadius: min(cornerRadius, body.height / 2), style: .continuous)
        }
        // Drawn in the tail-on-the-trailing-edge frame and mirrored afterwards, so one construction
        // serves both layout directions.
        let radius = min(cornerRadius, body.height / 2, body.width / 2)
        var path = Path()
        // Top edge and top-trailing corner.
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + radius),
            control: CGPoint(x: body.maxX, y: body.minY)
        )
        // Trailing edge keeps its wall until just above the bottom: the tail belongs to the bubble's
        // underside, not its side. Its measures are absolute, so the curl reads the same on a one-line
        // bubble and a tall one.
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 9))
        // Outer edge of the tail: the wall descends diagonally onto a tip resting on the bottom line,
        // barely past the trailing edge — the curl belongs to the underside, not the side.
        path.addCurve(
            to: CGPoint(x: body.maxX + Self.tailWidth, y: body.maxY),
            control1: CGPoint(x: body.maxX + 0.6, y: body.maxY - 4),
            control2: CGPoint(x: body.maxX + Self.tailWidth * 0.65, y: body.maxY - 1.2)
        )
        // Inner edge of the tail: rises well into the notch, so the lobe hangs below the underside's
        // sweep the way Messages draws it.
        path.addCurve(
            to: CGPoint(x: body.maxX - 8, y: body.maxY),
            control1: CGPoint(x: body.maxX - 0.6, y: body.maxY - 4.4),
            control2: CGPoint(x: body.maxX - 4.4, y: body.maxY - 0.6)
        )
        // Bottom edge, bottom-leading corner, leading edge, top-leading corner.
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - radius),
            control: CGPoint(x: body.minX, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: body.minX + radius, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        path.closeSubpath()

        guard tailEdge == .leading else {
            return path
        }
        return path.applying(
            CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.maxX - rect.minX, y: 0)
        )
    }
}
