//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveAccount
import SwiftUI

@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor(TestAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            AccountTestsView()
                .grove(appDelegate)
                .environment(\.features, appDelegate.features)
        }
    }
}
