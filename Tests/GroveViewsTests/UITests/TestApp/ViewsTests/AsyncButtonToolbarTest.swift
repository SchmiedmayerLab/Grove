//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


struct AsyncButtonToolbarTestSheet: View {
    @State private var cancelState: ViewState = .idle
    @State private var didCancel = false
    @State private var didFinishListRowAction = false
    @State private var didFinishOverlayAction = false
    @State private var didTap = false
    @State private var listRowState: ViewState = .idle
    @State private var overlayState: ViewState = .idle
    
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Did cancel", value: didCancel.description)
                LabeledContent("Did tap", value: didTap.description)
                Section("Role-only processing") {
                    AsyncButton(role: .confirm, state: $overlayState) {
                        try await Task.sleep(for: .seconds(2))
                        didFinishOverlayAction = true
                    }
                    .accessibilityIdentifier("Role Only Overlay")
                    LabeledContent("Overlay completed", value: didFinishOverlayAction.description)

                    AsyncButton(role: .confirm, state: $listRowState) {
                        try await Task.sleep(for: .seconds(2))
                        didFinishListRowAction = true
                    }
                    .asyncButtonProcessingStyle(.listRow)
                    .accessibilityIdentifier("Role Only List Row")
                    LabeledContent("List row completed", value: didFinishListRowAction.description)
                }
            }
            .navigationTitle("AsyncButtonInToolbar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AsyncButton(role: .cancel, state: $cancelState) {
                        didCancel = true
                    }
                    .accessibilityIdentifier("Role Only Cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    AsyncButton("Tap Me!") {
                        didTap = true
                    }
                }
            }
        }
    }
}
