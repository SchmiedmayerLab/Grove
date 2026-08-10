//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct TogglesAndSwitches: View {
    @State private var isOn = false
    
    var body: some View {
        Form {
            Toggle("Selection", isOn: $isOn)
                .accessibilityIdentifier("toggle:selection")
            LabeledContent("Selection Value", value: isOn.description)
        }
    }
}
