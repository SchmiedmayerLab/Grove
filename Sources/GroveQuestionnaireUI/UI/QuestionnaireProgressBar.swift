//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Keeps the sheet's progress bar in step with the page in front of the participant.
///
/// The bar belongs to the sheet rather than to a page: pages are pushed and popped beneath it, and it
/// stays where it is while its length eases to the next value.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
@MainActor
final class QuestionnaireProgressState {
    /// How much of the run is done, from 0 to 1; `nil` where there is no bar to show, before the first
    /// page reports and once the run is over.
    var fraction: Double?
    /// Where the pages' content begins, from the top of the sheet: the lower edge of the navigation bar.
    var contentTop: CGFloat = 0
}


/// Tells the sheet's bar how far this page is, and where the page's content begins.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PageProgressReporting: ViewModifier {
    /// The page's fraction of the run, or `nil` on a page that does not report: a follow-up sheet, or a run without a bar.
    let fraction: Double?

    @Environment(QuestionnaireProgressState.self) private var progressState: QuestionnaireProgressState?
    /// Whether the page is the one in front of the participant; a page behind it must not report for it.
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            // The page's safe area starts under the navigation bar, where the line belongs: an inset rather than a
            // frame, so it neither slides with a push nor rises with the sheet. A page on its way in reports none yet.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { contentTop in
                if fraction != nil, contentTop > 0 {
                    progressState?.contentTop = contentTop
                }
            }
            .onChange(of: fraction) { _, fraction in
                if isShowing, let fraction {
                    progressState?.fraction = fraction
                }
            }
            .onAppear {
                isShowing = true
                if let fraction {
                    progressState?.fraction = fraction
                }
            }
            .onDisappear {
                isShowing = false
            }
    }
}


/// A tinted line along the navigation bar's lower edge that grows as the pages pass.
///
/// No track of its own: the part not yet travelled stays clear, so the bar's own separator shows through.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuestionnaireProgressBar: View {
    static let height: CGFloat = 1

    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.tint)
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        // Smooth rather than snappy: the bar reports, it does not react, and it should be seen travelling.
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress", bundle: .module))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        .accessibilityIdentifier("QuestionnaireProgressBar")
    }
}
