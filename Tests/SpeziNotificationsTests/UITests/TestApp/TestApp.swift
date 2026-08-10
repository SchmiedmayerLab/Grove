//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziNotifications
import SwiftUI
import XCTSpeziNotificationsUI


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
            .spezi(appDelegate)
        }
        // for some reason, XCTest can't swipeUp() in visionOS (you can call the function; it just doesn't do anything),
        // so we instead need to make the window super large so that everything fits on screen without having to scroll.
        #if os(visionOS)
        .defaultSize(width: 1250, height: 1250)
        #endif
    }
}
