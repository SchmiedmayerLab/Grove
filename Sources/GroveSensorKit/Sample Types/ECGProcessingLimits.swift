//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Bounds immutable ECG facts retained while assembling complete sessions across native callbacks.
/// An entry is a voltage sample or a marker reading with no voltage samples. Encoded recording limits remain separate.
@available(iOS 17.4, *)
public struct SensorKitECGProcessingLimits: Hashable, Sendable {
    public enum ConfigurationError: Error { case invalidLimit }

    public let maximumEntries: Int
    public let maximumSessions: Int

    /// Allows one million entries and 128 sessions in one unacknowledged batch.
    public init() {
        maximumEntries = 1_000_000
        maximumSessions = 128
    }

    /// Capacity errors retain the acquisition cursor; callers may retry with a larger explicit budget.
    public init(maximumEntries: Int, maximumSessions: Int) throws {
        guard (1...Int(Int32.max)).contains(maximumEntries), (1...Int(Int32.max)).contains(maximumSessions) else {
            throw ConfigurationError.invalidLimit
        }
        self.maximumEntries = maximumEntries
        self.maximumSessions = maximumSessions
    }
}
