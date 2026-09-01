//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


extension View {
    private var formActionRowBase: some View {
        listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
    }

    /// Lays `content` out as the last row of the form, taking the same width as the cards.
    ///
    /// The action belongs at the end of the questions rather than pinned over them: a bar fixed
    /// to the bottom edge covers content on a long page and reads as chrome, and the participant
    /// arrives at the action by finishing the page.
    @ViewBuilder
    func formActionRow() -> some View {
        #if os(macOS)
        if #available(macOS 13, *) {
            formActionRowBase.listRowSeparator(.hidden)
        } else {
            formActionRowBase
        }
        #else
        formActionRowBase.listRowSeparator(.hidden)
        #endif
    }
}
