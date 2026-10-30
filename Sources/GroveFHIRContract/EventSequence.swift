//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A positive event sequence or key epoch in its canonical decimal wire form.
///
/// The protocol imposes no machine-integer ceiling, so the validated text is retained rather than
/// parsed through `UInt64`.
public struct EventSequence: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    public init(_ value: UInt64) {
        precondition(value > 0, "An event sequence or key epoch is positive.")
        self.rawValue = String(value)
    }

    public init(_ text: String) throws(ExchangeIdentityError) {
        guard CanonicalNonnegativeDecimal.isCanonical(text), text != "0" else {
            throw .invalidEventSequence(text)
        }
        self.rawValue = text
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let (left, right) = (lhs.rawValue.utf8.count, rhs.rawValue.utf8.count)
        return left == right ? lhs.rawValue < rhs.rawValue : left < right
    }
}
