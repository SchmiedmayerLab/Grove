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
            NavigationStack {
                ContentView()
            }
            .environment(responsesStore)
            .environment(sheetSettings)
        }
    }
}
