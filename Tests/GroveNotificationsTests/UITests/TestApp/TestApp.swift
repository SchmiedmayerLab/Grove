//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveNotifications
import SwiftUI
import XCTGroveNotificationsUI


@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor(TestAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Controls", systemImage: "switch.2") {
                    NavigationStack {
                        ControlsView()
                    }
                }
                Tab("Notifications", systemImage: "mail") {
                    NavigationStack {
                        NotificationsView()
                    }
                }
            }
            .grove(appDelegate)
        }
        // for some reason, XCTest can't swipeUp() in visionOS (you can call the function; it just doesn't do anything),
        // so we instead need to make the window super large so that everything fits on screen without having to scroll.
        #if os(visionOS)
        .defaultSize(width: 1250, height: 1250)
        #endif
    }
}
