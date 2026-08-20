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
/// One path rather than a rounded rectangle plus a decoration: two shapes drawn over each other seam
/// wherever the fill is not fully opaque, and the tail has to read as part of the bubble.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatBubbleShape: Shape {
    /// How far the tail reaches past the body of the bubble.
    static let tailWidth: CGFloat = 6

    let cornerRadius: CGFloat
    /// Which side the tail leaves from, so it stays on the sender's side in a right-to-left layout.
    let tailEdge: HorizontalEdge

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: tailEdge == .trailing ? rect.minX : rect.minX + Self.tailWidth,
            y: rect.minY,
            width: max(rect.width - Self.tailWidth, cornerRadius * 2),
            height: rect.height
        )
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        path.addPath(tail(from: body, in: rect))
        return path
    }

    /// The tail leaves the bottom corner going outwards and curves back into the underside, which is what
    /// gives it the flick rather than the wedge a straight triangle would draw.
    private func tail(from body: CGRect, in rect: CGRect) -> Path {
        let outward: CGFloat = tailEdge == .trailing ? 1 : -1
        let root = tailEdge == .trailing ? body.maxX : body.minX
        let tip = tailEdge == .trailing ? rect.maxX : rect.minX

        var path = Path()
        path.move(to: CGPoint(x: root, y: body.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: tip, y: body.maxY),
            control: CGPoint(x: root, y: body.maxY - cornerRadius * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: root - outward * cornerRadius * 0.6, y: body.maxY),
            control: CGPoint(x: root - outward * cornerRadius * 0.1, y: body.maxY)
        )
        path.closeSubpath()
        return path
    }
}
