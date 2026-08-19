//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Covers the `FoundationModels` entries in the test app.
///
/// Neither model runs in a simulator, so what is checked here is that the platform reports its availability and the
/// app says so, rather than presenting a chat that could never answer.
@MainActor
final class LLMFoundationModelsUITests: TestAppTestCase {
    func testBothModelsReportTheirAvailability() throws {
        guard #available(iOS 27, *) else {
            throw XCTSkip("The FoundationModels platform needs iOS 27.")
        }
        launch(
            enableMockMode: false,
            showOnboarding: false,
            clearAPIKeysFromKeychain: false,
            waitingFor: app.collectionViews.buttons["LLMFoundationModels On-Device"]
        )

        for entry in ["LLMFoundationModels On-Device", "LLMFoundationModels Private Cloud"] {
            let row = app.collectionViews.buttons[entry]
            XCTAssert(row.waitForExistence(timeout: 2), "\(entry) should be offered in the test app.")
            row.tap()

            // Either the model is there and a composer comes up, or the view says why it isn't.
            let composer = app.textFields["Message Input Textfield"]
            let unavailable = app.staticTexts["Model Unavailable"]
            XCTAssert(
                composer.waitForExistence(timeout: 5) || unavailable.waitForExistence(timeout: 5),
                "\(entry) should either offer a chat or explain why it cannot."
            )

            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
