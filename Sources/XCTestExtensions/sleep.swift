//
// This source file is part of the Stanford XCTestExtensions open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import func unistd.usleep


/// Suspends execution for the specified duration.
///
/// - Note: This exists as a synchronous alternative to [`Task.sleep(for:)`](https://developer.apple.com/documentation/swift/task/sleep(_:)),
///     in order to work around a bug in XCTest, where `async` UI test functions will sometimes hang at their suspension points.
@available(iOS 16, macOS 13, watchOS 9, visionOS 1, *)
public func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}


@available(iOS 16, macOS 13, watchOS 9, visionOS 1, *)
extension Duration {
    /// The number of seconds in the `Duration`, as a `TimeInterval` value.
    ///
    /// - Note: Copied from SpeziFoundation, so that we don't need to add that as a dependency.
    fileprivate var timeInterval: Double {
        let components = self.components
        let attosecondsInSeconds = Double(components.attoseconds) / 1_000_000_000_000_000_000.0 // 10^-18
        return Double(components.seconds) + attosecondsInSeconds
    }
}
