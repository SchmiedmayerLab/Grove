//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Floats `actions` over the bottom of a scrolling page.
    ///
    /// The actions sit in the bottom safe area inset, so the page scrolls to an end above them, and what runs
    /// underneath fades into a blur before it reaches a button. Use it for the primary and secondary actions of a step.
    public func floatingActions(@ViewBuilder _ actions: () -> some View) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            actions()
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .background {
                    // The blur reaches above the actions, so what scrolls under them has faded out before it
                    // touches a button, and the fade is long enough to be seen.
                    ProgressiveBlur(locations: [0, 0.4])
                        .padding(.top, -28)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
        }
    }

    /// Fades scrolling content out as it runs into the bottom safe area, with nothing floating over it.
    ///
    /// Use it for a page that is read to the end, such as a consent form, whose action sits in the content itself.
    /// The band is a real inset, so scrolling to the end, or to a control, stops above it.
    public func fadesIntoBottomEdge() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 24)
                .background {
                    ProgressiveBlur(locations: [0, 0.4])
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
        }
    }
}
