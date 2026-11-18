//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Bounds the ECG facts retained while sessions are assembled across native callbacks.
///
/// An entry is a voltage sample, or a marker reading without voltage samples. The limits of an encoded recording are
/// separate.
@available(iOS 17.4, *)
public struct SensorKitECGProcessingLimits: Hashable, Sendable {
    /// Why limits are invalid.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// A limit is outside 1 through `Int32.max`.
        case invalidLimit
    }

    /// The most entries one unacknowledged batch retains.
    public let maximumEntries: Int
    /// The most sessions one unacknowledged batch retains.
    public let maximumSessions: Int

    /// Limits that admit one million entries and 128 sessions in one unacknowledged batch.
    public init() {
        maximumEntries = 1_000_000
        maximumSessions = 128
    }

    /// Creates explicit limits.
    ///
    /// Exceeding a limit keeps the acquisition cursor, so a caller can retry with larger limits.
    ///
    /// - Parameters:
    ///   - maximumEntries: The most entries one unacknowledged batch retains, between 1 and `Int32.max`.
    ///   - maximumSessions: The most sessions one unacknowledged batch retains, between 1 and `Int32.max`.
    public init(maximumEntries: Int, maximumSessions: Int) throws(ConfigurationError) {
        guard (1...Int(Int32.max)).contains(maximumEntries), (1...Int(Int32.max)).contains(maximumSessions) else {
            throw .invalidLimit
        }
        self.maximumEntries = maximumEntries
        self.maximumSessions = maximumSessions
    }
}
