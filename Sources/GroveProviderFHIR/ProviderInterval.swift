//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A positive source interval with exact timestamp bounds and decimal seconds.
public struct ProviderInterval: Sendable, Hashable {
    public let start: ProviderTimestamp
    public let end: ProviderTimestamp

    public var duration: Decimal {
        Decimal(end.secondsSinceEpoch - start.secondsSinceEpoch)
            + Decimal(end.nanoseconds - start.nanoseconds) / 1_000_000_000
    }

    public init(start: ProviderTimestamp, end: ProviderTimestamp) throws {
        guard start < end else { throw ProviderConversionError.invalidInterval }
        self.start = start
        self.end = end
    }
}
