//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziViews
import SwiftUI
import XCTestApp


final class TestDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            ConfigureTipKit()
        }
    }
}


@main
struct UITestsApp: App {
    @ApplicationDelegateAdaptor(TestDelegate.self) private var delegate

    private var shouldOpenAsyncButtonDebounceTest: Bool {
        CommandLine.arguments.contains("--async-button-debounce-test")
            || ProcessInfo.processInfo.environment["SPEZI_ASYNC_BUTTON_DEBOUNCE_TEST"] == "1"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldOpenAsyncButtonDebounceTest {
                    AsyncButtonDebounceTestView()
                } else {
                    SpeziViewsTargetsTests()
                }
            }
                .spezi(delegate)
        }
    }
}
