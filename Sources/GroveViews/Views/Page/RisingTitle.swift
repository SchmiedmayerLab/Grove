//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


private struct RisingTitlePreferenceKey: PreferenceKey {
    static let defaultValue: RisingTitle? = nil

    static func reduce(value: inout RisingTitle?, nextValue: () -> RisingTitle?) {
        value = nextValue() ?? value
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct RisingTitleModifier: ViewModifier {
    let title: String
    let subtitle: String?

    @State private var bottom: CGFloat = 0
    @Environment(\.risingTitleIsInBar) private var isInBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // One title at a time: as the bar takes it, the copy in the content fades and lifts, and settles back
            // the same way when the bar lets go. The frame stays, so the measurement below is unaffected.
            .opacity(isInBar ? 0 : 1)
            .offset(y: isInBar && !reduceMotion ? -6 : 0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxY
            } action: { bottom in
                self.bottom = bottom
            }
            .preference(key: RisingTitlePreferenceKey.self, value: RisingTitle(title: title, subtitle: subtitle, bottom: bottom))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct AcceptsRisingTitleModifier: ViewModifier {
    @State private var title: String?
    @State private var subtitle: String?
    /// Where the title ends, measured from the top of the content.
    @State private var titleBottom: CGFloat?
    @State private var top: CGFloat = 0
    @State private var scrolled: CGFloat = 0
    @State private var titleIsUnderBar = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                self.top = top
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, scrolled in
                self.scrolled = scrolled
                setTitleIsUnderBar(scrolled > (titleBottom ?? .infinity))
            }
            // The title reports where it ends on screen; the page keeps that as a distance from the top of its
            // content, so a list that drops the title's row once it has scrolled far enough away leaves the bar as it is.
            .environment(\.risingTitleIsInBar, titleIsUnderBar)
            .onPreferenceChange(RisingTitlePreferenceKey.self) { risingTitle in
                guard let risingTitle else {
                    return
                }
                title = risingTitle.title
                subtitle = risingTitle.subtitle
                titleBottom = risingTitle.bottom - top + scrolled
                setTitleIsUnderBar(risingTitle.bottom < top)
            }
            #if !os(macOS)
            // Every page keeps its navigation bar, the first one included, so titles sit at one height throughout a flow.
            // Inline, or an empty large-title bar would hold fifty points of nothing above the page's own title.
            .toolbar(.visible, for: .navigationBar)
            .toolbarTitleDisplayMode(.inline)
            #endif
            #if os(iOS) || os(visionOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let title, titleIsUnderBar {
                        VStack(spacing: 0) {
                            Text(title)
                                .font(.headline)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
            }
            #endif
    }

    private func setTitleIsUnderBar(_ isUnderBar: Bool) {
        guard isUnderBar != titleIsUnderBar else {
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            titleIsUnderBar = isUnderBar
        }
    }
}


/// What the navigation bar shows once the page's own title has scrolled under it.
private struct RisingTitle: Equatable {
    let title: String
    let subtitle: String?
    /// Where the title ends on screen.
    let bottom: CGFloat
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Lets a page title move up into the navigation bar once it has scrolled out of view.
    ///
    /// Apply it to the title inside the scrolling content of a page that ``acceptsRisingTitle()``.
    /// The title measures where it ends; the page shows `title` in the bar once that edge has passed under it,
    /// with `subtitle` in small type beneath it, the way the bar sets a subtitle of its own.
    public func risesIntoNavigationBar(_ title: String, subtitle: String? = nil) -> some View {
        modifier(RisingTitleModifier(title: title, subtitle: subtitle))
    }

    /// Shows a rising title in the navigation bar once the page has scrolled past it.
    ///
    /// Apply it to the scroll view, list or form of a page that holds a title that ``risesIntoNavigationBar(_:subtitle:)``.
    /// The bar stays visible and inline so every page of a flow sets its title at the same height, and the principal
    /// item fades in as the page's own title leaves.
    public func acceptsRisingTitle() -> some View {
        modifier(AcceptsRisingTitleModifier())
    }
}


extension EnvironmentValues {
    /// Whether the page's title is being shown in the navigation bar, so the copy in the content steps aside.
    @Entry var risingTitleIsInBar = false
}
