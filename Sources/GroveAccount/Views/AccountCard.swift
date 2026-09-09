//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// The card every account form puts its rows on; sign-in, sign-up and the setup page share it with the onboarding views.
    func accountCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return self
            .background(.fill.quaternary, in: shape)
            .clipShape(shape)
    }

    /// One row on an ``accountCard()``: it takes the blocking tint across the card's full width, the way a form row does.
    func accountCardRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .highlightsBlockingContent()
    }
}
