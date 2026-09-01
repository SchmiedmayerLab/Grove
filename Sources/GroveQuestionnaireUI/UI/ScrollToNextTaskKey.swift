//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// `@Entry` warns that a closure in the environment invalidates every dependent on each
/// update, because closures cannot be compared; a key of our own stores the same value
/// without the macro's diagnostic.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct ScrollToNextTaskKey: EnvironmentKey {
    static var defaultValue: () -> Void { {} }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// Moves the participant on to the next question they can answer.
    var scrollToNextTask: () -> Void {
        get { self[ScrollToNextTaskKey.self] }
        set { self[ScrollToNextTaskKey.self] = newValue }
    }
}
