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
    /// Fades a list or form into the navigation bar the way a scroll view does.
    ///
    /// On iOS 26 a `ScrollView` gets a soft gradient under the bar, but a `List` or `Form` a hard line;
    /// this gives them the gradient too. Earlier systems are left as they are.
    @ViewBuilder
    public func softScrollEdge() -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #endif
    }
}
