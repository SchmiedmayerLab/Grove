//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@main
struct UITestsApp: App {
    @State private var responsesStore = ResponsesStore()
    @State private var sheetSettings = SheetSettings()
    @State private var path = LaunchShortcut.page.map { [$0] } ?? []

    init() {
        #if os(iOS)
        // Nothing animates on a host that has turned animations off, which a page has to cope with as well.
        if ProcessInfo.processInfo.arguments.contains("--disableAnimations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                ContentView()
            }
            .environment(responsesStore)
            .environment(sheetSettings)
        }
    }
}
