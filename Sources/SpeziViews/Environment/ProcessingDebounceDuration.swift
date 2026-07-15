//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// A `Duration` that provides a generalized configuration for debounce durations for any processing-related operations.
    ///
    /// This might be helpful to provide extensive customization points without introducing clutter in the initializer of views.
    /// The ``AsyncButton`` is one example where this `EnvironmentKey` is used.
    ///
    /// - Note: The default value is `150ms`.
    @Entry public var processingDebounceDuration: Duration = .milliseconds(150)
}
