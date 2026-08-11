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
    @State private var didTap = false
    
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Did tap", value: didTap.description)
            }
            .navigationTitle("AsyncButtonInToolbar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissButton()
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
