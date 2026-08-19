//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveViews
import SwiftUI
import XCTestApp


final class TestDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            ConfigureTipKit()
        }
    }
}


@main
struct UITestsApp: App {
    @ApplicationDelegateAdaptor(TestDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            GroveViewsTargetsTests()
                .grove(delegate)
        }
    }
}
