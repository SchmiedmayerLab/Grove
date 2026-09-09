//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


struct PageActionsTestView: View {
    private enum HeldBack: String, CaseIterable {
        case none = "None"
        case primary = "Primary"
        case secondary = "Secondary"
    }

    @State private var heldBack: HeldBack = .primary

    var body: some View {
        PageView {
            PageHeader(title: "Page Actions")
        } content: {
            Picker("Held back", selection: $heldBack) {
                ForEach(HeldBack.allCases, id: \.self) { choice in
                    Text(choice.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            PageActions(primaryTitle: "Waiting", primaryAction: {}, secondaryTitle: "Skip", secondaryAction: {})
                .actionButtonDisabled(.primary, heldBack == .primary)
                .actionButtonDisabled(.secondary, heldBack == .secondary)
        }
    }
}
