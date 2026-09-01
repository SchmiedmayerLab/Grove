//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A positive base-10 integer in its canonical wire representation.
///
/// Like ``CanonicalNonnegativeDecimal``, this type has no implementation-defined maximum.
public struct CanonicalPositiveDecimal: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    public init(_ rawValue: String) throws(CanonicalDecimalError) {
        guard CanonicalNonnegativeDecimal.isCanonical(rawValue), rawValue != "0" else {
            throw .invalidPositiveDecimal(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(_ value: UInt64) throws(CanonicalDecimalError) {
        guard value > 0 else {
            throw .invalidPositiveDecimal(String(value))
        }
        self.rawValue = String(value)
    }
}
