//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import XCTest


extension XCUIApplication {
    /// Launches the application and waits until it is ready to be interacted with.
    ///
    /// [`launch()`](https://developer.apple.com/documentation/xctest/xcuiapplication/launch()) returns before the first frame is on
    /// screen, so an assertion made right after it races the cold launch. Pass the first element the test touches to wait for it instead.
    ///
    /// - Parameters:
    ///   - element: The element whose hittability marks the app as ready. Passing `nil` only waits for the app to reach `.runningForeground`.
    ///   - timeout: How long to wait, in seconds.
    /// - Returns: Whether the app, and `element` if one was given, became ready within the timeout.
    @discardableResult
    public func launchAndWait(for element: XCUIElement? = nil, timeout: TimeInterval = 30) -> Bool {
        launch()
        guard wait(for: .runningForeground, timeout: timeout) else {
            return false
        }
        guard let element else {
            return true
        }
        return element.wait(for: \.isHittable, toEqual: true, timeout: timeout)
    }
}
