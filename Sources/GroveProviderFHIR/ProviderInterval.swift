//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A positive source interval between two exact timestamps.
public struct ProviderInterval: Sendable, Hashable {
    /// The start.
    public let start: ProviderTimestamp
    /// The end, after the start.
    public let end: ProviderTimestamp

    /// The duration in seconds, exact to the nanosecond.
    public var duration: Decimal {
        Decimal(end.secondsSinceEpoch - start.secondsSinceEpoch)
            + Decimal(end.nanoseconds - start.nanoseconds) / 1_000_000_000
    }

    /// Creates an interval, refusing one whose end is not after its start.
    public init(start: ProviderTimestamp, end: ProviderTimestamp) throws(ProviderConversionError) {
        guard start < end else {
            throw .invalidInterval
        }
        self.start = start
        self.end = end
    }
}
