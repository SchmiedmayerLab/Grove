//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveScheduler
import GroveSchedulerUI
import SwiftUI


@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor(TestAppDelegate.self)
    var appDelegate
    
    
    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                // The documentation shows the schedule itself; a tab bar for the test app's other screen is
                // chrome that a study embedding the schedule would not have.
                if ProcessInfo.processInfo.arguments.contains("--documentation") {
                    ScheduleView()
                } else {
                    TabView {
                        Tab("Schedule", systemImage: "list.clipboard.fill") {
                            ScheduleView()
                        }
                        Tab("Notifications", systemImage: "mail.fill") {
                            NotificationsView()
                        }
                    }
                }
            }
            .grove(appDelegate)
        }
        // for some reason, XCTest can't swipeUp() in visionOS (you can call the function; it just doesn't do anything),
        // so we instead need to make the window super large so that everything fits on screen without having to scroll.
        .defaultSize(width: 1250, height: 1250)
    }
}
