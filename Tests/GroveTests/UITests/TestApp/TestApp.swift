//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import SwiftUI
import XCTestApp


@main
struct UITestsApp: App {
    @ApplicationDelegateAdaptor(TestAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TestAppTestsView<GroveTests>()
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        ModuleWithServiceView()
                    }
                }
                .grove(appDelegate)
        }
    }
}
