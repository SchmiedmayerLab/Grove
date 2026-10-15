//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
import MarkdownUI
import SwiftUI


/// A document hierarchy beneath the enclosing screen title, without shrinking deep headings below body text.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ConsentMarkdownStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .markdownBlockStyle(\.heading1) { heading($0, level: 1) }
            .markdownBlockStyle(\.heading2) { heading($0, level: 2) }
            .markdownBlockStyle(\.heading3) { heading($0, level: 3) }
            .markdownBlockStyle(\.heading4) { heading($0, level: 4) }
            .markdownBlockStyle(\.heading5) { heading($0, level: 5) }
            .markdownBlockStyle(\.heading6) { heading($0, level: 6) }
    }

    private func heading(_ configuration: BlockConfiguration, level: Int) -> some View {
        // MarkdownUI scales its base font with Dynamic Type. Relative sizes preserve that scaling.
        let headingSizes: [CGFloat] = [22, 20, 19, 18, 17, 17]
        let scale = headingSizes[level - 1] / 17
        let accessibilityLevel: AccessibilityHeadingLevel = [.h1, .h2, .h3, .h4, .h5, .h6][level - 1]
        return configuration.label
            .markdownTextStyle {
                FontSize(.em(scale))
                FontWeight(level == 6 ? .semibold : .bold)
                FontStyle(level == 6 ? .italic : .normal)
            }
            .markdownMargin(top: .rem(1), bottom: .rem(0.5))
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(accessibilityLevel)
    }
}
#endif
