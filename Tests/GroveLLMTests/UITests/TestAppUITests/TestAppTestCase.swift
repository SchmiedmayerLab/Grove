//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


@MainActor
class TestAppTestCase: XCTestCase, Sendable {
    let app = XCUIApplication()
    
    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    
    func launch(
        enableMockMode: Bool,
        showOnboarding: Bool,
        clearAPIKeysFromKeychain: Bool,
        waitingFor element: XCUIElement? = nil
    ) {
        app.launchArguments = []
        if enableMockMode {
            app.launchArguments.append("--mockMode")
        }
        if showOnboarding {
            app.launchArguments.append("--showOnboarding")
        }
        if clearAPIKeysFromKeychain {
            app.launchArguments.append("--resetSecureStorage")
        }
        XCTAssert(app.launchAndWait(for: element), "The app did not become ready after launch.")
    }
}
