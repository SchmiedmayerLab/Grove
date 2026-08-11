//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import SwiftUI


@main
struct UITestsApp: App {
    @ApplicationDelegateAdaptor(TestAppDelegate.self) var appDelegate
    
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MenuView()
            }
            .grove(appDelegate)
        }
    }
}

struct MenuView: View {
    var body: some View {
        List {
            NavigationLink(destination: SpeechTestView()) {
                Text("Speech Test View")
            }
            NavigationLink(destination: SpeechVoiceSelectionTestView()) {
                Text("Speech Voice Selection Test View")
            }
        }
        .navigationTitle("Grove Speech Tests")
    }
}
