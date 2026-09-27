//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest


extension QuestionnaireSheetNavigator {
    /// The bar under the navigation bar, on the questionnaires that asked for one.
    public var progressBar: XCUIElement {
        app.otherElements["QuestionnaireProgressBar"]
    }

    /// How far the bar has filled, from 0 to 1, or `nil` without a bar.
    public var progress: Double? {
        guard progressBar.exists, let value = progressBar.value as? String else {
            return nil
        }
        return Double(value.filter { $0.isNumber }).map { $0 / 100 }
    }

    /// Whether the bar fills to `fraction` within the timeout; the bar rounds to whole percent.
    public func waitUntilProgress(_ fraction: Double, timeout: TimeInterval = Self.defaultTimeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let progress, abs(progress - fraction) <= 0.01 {
                return true
            }
            usleep(200_000)
        } while Date() < deadline
        return false
    }
}
