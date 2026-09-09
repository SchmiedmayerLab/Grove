//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// A full page with a header and content that scroll, and actions that float over them.
///
/// ![A page with a title, information areas and a floating primary button.](Welcome)
///
/// Onboarding, account, consent and questionnaire pages are all built on it, so they read the same way. The header
/// and content scroll; the footer floats over them at the bottom, and the content fades into a blur as it runs
/// underneath. A ``PageHeader`` can carry an image above the title, and once the title scrolls out of view it appears
/// in the navigation bar instead. A page that has to be read to the end, such as a consent form, leaves the footer
/// out and puts its action in the content; the content then fades out into the bottom safe area only.
///
/// ```swift
/// PageView {
///     PageHeader(title: "Title", subtitle: "Subtitle")
/// } content: {
///     Text("The page's content.")
/// } footer: {
///     PageActions("Continue") {
///         // move on to the next page
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct PageView<Header: View, Content: View, Footer: View>: View {
    @Environment(\.verticalScrollIndicatorVisibility) private var scrollIndicatorVisibility
    @Environment(\.isInManagedNavigationStack) private var isInManagedNavigationStack
    @Environment(\.pageEdgesWithPaddingDisabled) private var edgesWithPaddingDisabled

    private let wrapInScrollView: Bool
    private let header: Header
    private let content: Content
    private let footer: Footer

    @_documentation(visibility: internal)
    public var body: some View {
        if footer is EmptyView {
            page.fadesIntoBottomEdge()
        } else {
            page.floatingActions {
                footer
            }
        }
    }

    private var page: some View {
        GeometryReader { geometry in
            if wrapInScrollView {
                ScrollView {
                    makeContents(geometry: geometry)
                }
                .scrollIndicators(effectiveScrollIndicatorVisibility, axes: .vertical)
                .acceptsRisingTitle()
            } else {
                makeContents(geometry: geometry)
            }
        }
    }

    /// The set of edges for which we want to apply implicit padding.
    ///
    /// - Note: The bottom edge is padded separately, below the content and above the floating footer.
    private var edgesWithImplicitPadding: Edge.Set {
        // if the view is used as part of an `ManagedNavigationStack`, we don't want the extra padding at the top,
        // since that's where the navigation bar will be and we're already getting some padding via that.
        let edges: Edge.Set = isInManagedNavigationStack ? .horizontal : [.horizontal, .top]
        return edges.subtracting(edgesWithPaddingDisabled)
    }

    private var effectiveScrollIndicatorVisibility: ScrollIndicatorVisibility {
        let visibility = scrollIndicatorVisibility
        return visibility == .automatic ? .hidden : visibility
    }


    /// Creates a page from its header, content and footer.
    ///
    /// - Parameters:
    ///   - wrapInScrollView: Whether the page wraps its header, content and footer in a `ScrollView`.
    ///       Defaults to `true`; pass `false` when the content already scrolls, such as a `Form`, to avoid nested `ScrollView`s.
    ///   - header: The header view displayed at the top.
    ///   - content: The content view.
    ///   - footer: Actions that float over the scrolling content at the bottom. Leave it out for a page whose
    ///       content has to be read to the end, such as a consent form, and put the action in the content instead.
    public init(
        wrapInScrollView: Bool = true,
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.wrapInScrollView = wrapInScrollView
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    /// Creates a page whose content is read to the end, with nothing floating over it.
    ///
    /// Use it for a page such as a consent form, where the action belongs below the content rather than over it.
    /// The content still fades out into the bottom safe area as it scrolls.
    ///
    /// - Parameters:
    ///   - wrapInScrollView: Whether the page wraps its body in a `ScrollView`; see ``init(wrapInScrollView:header:content:footer:)``.
    ///   - header: The header view displayed at the top.
    ///   - content: The content view.
    public init(
        wrapInScrollView: Bool = true,
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(wrapInScrollView: wrapInScrollView, header: header, content: content) {
            EmptyView()
        }
    }


    @ViewBuilder
    private func makeContents(geometry: GeometryProxy) -> some View {
        VStack {
            header
            content
        }
        .padding(edgesWithImplicitPadding)
        .padding(.bottom, edgesWithPaddingDisabled.contains(.bottom) ? 0 : 10)
        // The geometry already stops above the floating actions or the bottom band, so the content fills it exactly.
        .frame(minHeight: geometry.size.height, alignment: .top)
        .frame(maxWidth: .infinity)
    }
}


extension EnvironmentValues {
    @Entry fileprivate var pageEdgesWithPaddingDisabled: Edge.Set = []
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PageView {
    /// Disables the page's implicit padding for the specified edges.
    ///
    /// If this modifier is applied multiple times, the outermost call will take precedence.
    ///
    /// - Note: Inside a ``ManagedNavigationStack`` the top edge is already disabled implicitly.
    public func disablePadding(_ edges: Edge.Set) -> some View {
        self.environment(\.pageEdgesWithPaddingDisabled, edges)
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    PageView {
        PageHeader(title: String("Title"), subtitle: String("Subtitle"))
    } content: {
        Text(verbatim: "This is a PC. And we can write a lot about PCs in a section like this. A very long text!")
    } footer: {
        PageActions("Primary Button") {
            print("Primary!")
        }
    }
}
#endif
