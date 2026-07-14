//
// This source file is part of the Stanford XCTestExtensions open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
public import XCUIAutomation


extension XCUIElement {
    /// The `XCUIApplication` to whose view hierarchy this element belongs.
    public var app: XCUIApplication {
        get throws {
            if let self = self as? XCUIApplication {
                return self
            } else if let app = self.value(forKey: "application") as? XCUIApplication {
                return app
            } else {
                throw XCTestError(.failureWhileWaiting, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to obtain XCUIApplication for \(self.debugDescription)"
                ])
            }
        }
    }
}
