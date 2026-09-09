//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Stands in for a picture the assistant is still drawing: a field of dots that a soft wave sketches across, the way
/// a picture resolves. It fills whatever frame it is given, so it can grow into the picture's before giving way to it.
///
/// Under Reduce Motion the dots hold still and the card reads as a plain placeholder.
@available(iOS 18, macOS 15, watchOS 11, *)
struct GeneratingImageView: View {
    private static let spacing: CGFloat = 11
    private static let dotRadius: CGFloat = 1.4
    /// One pass of the wave covers this much of the field's diagonal, in points.
    private static let wavelength: CGFloat = 520

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                dots(at: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                    dots(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.fill.quinary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("GENERATING_IMAGE", bundle: .module))
    }

    /// Two soft crests sweeping from the top-left to the bottom-right, six seconds per pass, over a faint floor.
    ///
    /// The wave is a function of position in points, not of the dot's place in the grid, so it keeps moving
    /// continuously while the frame changes size.
    private static func brightness(at point: CGPoint, time: TimeInterval) -> Double {
        let position = (point.x + point.y) / wavelength
        let phase = (position - time / 6).truncatingRemainder(dividingBy: 0.5)
        let wave = cos((phase / 0.5) * 2 * .pi)
        return 0.15 + 0.6 * max(0, wave) * max(0, wave)
    }

    /// A grid of dots lit by a diagonal wave that drifts through the field; `nil` holds every dot at rest.
    ///
    /// The grid is anchored at the top-left, so a growing frame adds dots at its far edges instead of shifting them all.
    private func dots(at time: TimeInterval?) -> some View {
        Canvas { context, size in
            let columns = Int(size.width / Self.spacing)
            let rows = Int(size.height / Self.spacing)
            for column in 0..<columns {
                for row in 0..<rows {
                    let center = CGPoint(
                        x: (CGFloat(column) + 0.5) * Self.spacing,
                        y: (CGFloat(row) + 0.5) * Self.spacing
                    )
                    let rect = CGRect(origin: center, size: .zero).insetBy(dx: -Self.dotRadius, dy: -Self.dotRadius)
                    let brightness = time.map { Self.brightness(at: center, time: $0) } ?? 0.35
                    context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(brightness)))
                }
            }
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    GeneratingImageView()
        .frame(width: 280, height: 150)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .padding()
}
#endif
