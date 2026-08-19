//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import SwiftUI


@main
struct UITestsApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    NavigationLink("Sandbox Detection") {
                        SandboxDetectionTests()
                    }
                    NavigationLink("Local Preferences") {
                        LocalPreferencesTests()
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}
