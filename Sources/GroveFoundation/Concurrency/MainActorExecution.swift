//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Runs or schedules a closure on the `MainActor`, depending on the current execution context.
///
/// If the function is already running on the `MainActor`, the closure will be invoked immediately.
/// Otherwise, an invocation of the closure will be scheduled onto the `MainActor`.
///
/// - Important: Do not use this method as it breaks structured concurrency. Instead you might choose to use a combination of the `task(_:)` modifier and an `AsyncStream` to schedule work
///     onto the MainActor. If working within Grove Modules, explore the `ServiceModule` protocol to add structured concurrency support to your Module.
@available(
    *, deprecated, message: "Do not use this method as it breaks structured concurrency. Consider using other mechanisms like an AsyncStream."
)
public func runOrScheduleOnMainActor(
    _ block: @MainActor @escaping () -> Void
) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            block()
        }
    } else {
        Task { @MainActor in
            block()
        }
    }
}
