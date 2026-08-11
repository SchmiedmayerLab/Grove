//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The result of a connection attempt.
public enum ConnectionAttemptResult: Sendable {
    /// The connection attempt was successful and the device is connected.
    case success
    /// The connection attempt failed and will not be retried.
    ///
    /// This is the case upon `CancellationErrors` or if the underlying Bluetooth central is not ready (e.g., in state shutdown).
    case failed(cause: any Error)
    /// The connection attempt failed with the provided cause.
    ///
    /// It will be retried at a later point in time.
    case retry(cause: any Error)
}
