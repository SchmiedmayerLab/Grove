//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


extension XCUIApplication {
    /// Opens one of the targets listed on the app's root screen.
    ///
    /// - Parameters:
    ///   - target: The target's title in the root list.
    ///   - element: An element of the presented sheet to wait for. The sheet is presented asynchronously, so anything that touches its content
    ///     without first looking up an element of its own (a swipe, for example) races the presentation.
    ///   - timeout: How long to wait for each step, in seconds.
    func open(target: String, waitingFor element: XCUIElement? = nil, timeout: TimeInterval = 15.0) {
        XCTAssertTrue(staticTexts["Targets"].waitForExistence(timeout: timeout))
        let targetButton = buttons[target]
        XCTAssertTrue(targetButton.wait(for: \.isHittable, toEqual: true, timeout: timeout))
        targetButton.tap()
        if let element {
            XCTAssertTrue(element.waitForExistence(timeout: timeout))
        }
    }
}
