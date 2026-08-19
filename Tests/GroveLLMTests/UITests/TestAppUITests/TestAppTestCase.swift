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
        // Forward a provider token to the app when the runner was given one, so a live UI test never has to type a
        // secret through the interface. Which process receives it depends on how the run was invoked.
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["OPENAI_API_TOKEN"] ?? environment["TEST_RUNNER_OPENAI_API_TOKEN"], !token.isEmpty {
            app.launchEnvironment["OPENAI_API_TOKEN"] = token
        }
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


    /// Waits for rendered text even when SwiftUI exposes it as multiple accessibility elements.
    ///
    /// Streaming and Markdown rendering can legitimately split one visible message into several static texts.
    /// Joining their labels verifies what the person sees without depending on that implementation detail.
    func assertRenderedText(
        _ expectedText: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate { object, _ in
            guard let app = object as? XCUIApplication else {
                return false
            }
            let renderedText = app.staticTexts.allElementsBoundByIndex.map(\.label).joined()
            return renderedText.contains(expectedText)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(
            result,
            .completed,
            "Expected rendered text '\(expectedText)'. Static-text labels: \(labels)",
            file: file,
            line: line
        )
    }
}
