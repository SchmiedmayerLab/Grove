//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// A page title with an optional subtitle and an optional image above them.
///
/// ![A page whose header is a symbol above the title and subtitle.](ImageHeader)
///
/// ```swift
/// PageHeader(title: "Title", subtitle: "Subtitle")
/// PageHeader(title: "Health Access", subtitle: "Subtitle", image: Image(systemName: "heart.text.square"))
/// ```
///
/// The image is drawn large, centered and tinted, the way a symbol heads a permission or feature page. Inside a
/// ``PageView``, the title moves up into the navigation bar once it has scrolled out of view. A header that opens a page leaves room around itself; one heading a form right
/// under the navigation bar takes ``Spacing/compact`` and leaves the spacing to the form.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct PageHeader: View {
    /// The room a header leaves around itself.
    public enum Spacing {
        /// Room above and below, for a header that opens a page.
        case regular
        /// None, for a header right under the navigation bar in a form that spaces its sections itself.
        case compact
    }

    private let image: AnyView?
    private let title: Text
    private let barTitle: String
    private let subtitle: Text?
    /// The subtitle as the navigation bar shows it under the risen title, where it is to rise along.
    private let barSubtitle: String?
    private let spacing: Spacing

    @Environment(\.risingTitleIsInBar) private var isInBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @_documentation(visibility: internal)
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                image
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .padding(.top, spacing == .regular ? 44 : 12)
                    .padding(.bottom, 40)
                    .accessibilityHidden(true)
            }
            title
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("PageTitle")
                .risesIntoNavigationBar(barTitle, subtitle: barSubtitle)
            if let subtitle {
                subtitle
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    // Along with the title, when the bar takes it too.
                    .opacity(isInBar && barSubtitle != nil ? 0 : 1)
                    .offset(y: isInBar && barSubtitle != nil && !reduceMotion ? -6 : 0)
            }
        }
        .padding(.top, image == nil && spacing == .regular ? 32 : 0)
        .padding(.bottom, spacing == .regular ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        // needed to prevent the last line from being cut off in some edge cases
        // (not sure what's triggering this but it typically occurs when adding a step that just fits in the remaining space...)
        .fixedSize(horizontal: false, vertical: true)
    }

    private init(image: AnyView?, title: Text, barTitle: String, subtitle: Text?, barSubtitle: String?, spacing: Spacing) {
        self.image = image
        self.title = title
        self.barTitle = barTitle
        self.subtitle = subtitle
        self.barSubtitle = barSubtitle
        self.spacing = spacing
    }

    /// Creates a header with a title, an optional subtitle and an optional image above them.
    /// - Parameters:
    ///   - title: The localized title.
    ///   - subtitle: The optional localized subtitle.
    ///   - subtitleRises: Whether the subtitle rises into the navigation bar along with the title. For a name
    ///     rather than a sentence: the bar sets it small, on one line.
    ///   - spacing: The room left above the header.
    ///   - image: A symbol or picture shown large and tinted above the title.
    public init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        subtitleRises: Bool = false,
        spacing: Spacing = .regular,
        image: Image? = nil
    ) {
        self.init(
            image: image.map(Self.tinted),
            title: Text(title),
            barTitle: String(localized: title),
            subtitle: subtitle.map { Text($0) },
            barSubtitle: subtitleRises ? subtitle.map { String(localized: $0) } : nil,
            spacing: spacing
        )
    }

    /// Creates a header with a title, an optional subtitle and an optional image above them.
    /// - Parameters:
    ///   - title: The title.
    ///   - subtitle: The optional subtitle.
    ///   - subtitleRises: Whether the subtitle rises into the navigation bar along with the title. For a name
    ///     rather than a sentence: the bar sets it small, on one line.
    ///   - spacing: The room left above the header.
    ///   - image: A symbol or picture shown large and tinted above the title.
    @_disfavoredOverload
    public init(
        title: some StringProtocol,
        subtitle: (some StringProtocol)? = String?.none,
        subtitleRises: Bool = false,
        spacing: Spacing = .regular,
        image: Image? = nil
    ) {
        self.init(
            image: image.map(Self.tinted),
            title: Text(title),
            barTitle: String(title),
            subtitle: subtitle.map { Text($0) },
            barSubtitle: subtitleRises ? subtitle.map { String($0) } : nil,
            spacing: spacing
        )
    }

    private static func tinted(_ image: Image) -> AnyView {
        AnyView(
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        )
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PageHeader(title: String("Title"), subtitle: String("Subtitle"), image: Image(systemName: "heart.text.square"))
}
#endif
