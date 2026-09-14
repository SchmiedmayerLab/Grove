//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//
import SwiftUI


/// The speaker's voice as it was heard, bar by bar, newest at the right, scrolling on once the row is full.
///
/// The one sign that the microphone is hearing anything: a symbol that merely pulses says the recorder is on,
/// not that it is picking the speaker up.
@available(iOS 18, macOS 15, watchOS 11, *)
struct DictationWaveform: View {
    private static let barWidth: CGFloat = 2
    private static let spacing: CGFloat = 2

    /// How loud the speaker was, from 0 to 1, oldest first.
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let capacity = max(1, Int(size.width / (Self.barWidth + Self.spacing)))
            let shown = levels.suffix(capacity)
            for (index, level) in shown.enumerated() {
                let height = max(Self.barWidth, size.height * CGFloat(min(max(level, 0), 1)))
                let bar = CGRect(
                    x: CGFloat(index) * (Self.barWidth + Self.spacing),
                    y: (size.height - height) / 2,
                    width: Self.barWidth,
                    height: height
                )
                context.fill(Path(roundedRect: bar, cornerRadius: Self.barWidth / 2), with: .color(.red))
            }
        }
        .accessibilityHidden(true)
    }
}
