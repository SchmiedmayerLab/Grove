//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI

struct OnboardingTestViewNotIdentifiable: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    
    let text: String
    
    var body: some View {
        VStack(spacing: 12) {
            Text(self.text)

            Button {
                path.nextStep()
            } label: {
                Text("Next")
            }
        }
    }
}
