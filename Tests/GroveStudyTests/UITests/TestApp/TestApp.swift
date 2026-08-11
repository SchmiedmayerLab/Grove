//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveFoundation
import GroveStudy
import SwiftUI
import UniformTypeIdentifiers


@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor(TestAppDelegate.self)
    private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house") {
                    HomeTab()
                        .injectingCustomTaskCategoryAppearances()
                }
            }
            .grove(appDelegate)
            .onAppear {
                let fileManager = FileManager.default
                let studyBundles = ((try? fileManager.contents(of: .temporaryDirectory)) ?? [])
                    .filter { $0.pathExtension == UTType.studyBundle.preferredFilenameExtension }
                for url in studyBundles {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}
