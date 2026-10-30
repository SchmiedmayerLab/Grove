//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public enum CanonicalDecimalError: Error, Equatable, Sendable {
    case invalidNonnegativeDecimal(String)
    case invalidPositiveDecimal(String)
}


/// An unsigned base-10 integer in its canonical wire representation.
///
/// The exchange protocol deliberately does not impose a machine-integer upper bound. This value
/// therefore retains the validated decimal text instead of parsing it through `UInt64`.
public struct CanonicalNonnegativeDecimal: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    public init(_ rawValue: String) throws(CanonicalDecimalError) {
        guard Self.isCanonical(rawValue) else {
            throw .invalidNonnegativeDecimal(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(_ value: UInt64) {
        self.rawValue = String(value)
    }

    static func isCanonical(_ value: String) -> Bool {
        guard let first = value.utf8.first else {
            return false
        }
        if first == 0x30 {
            return value.utf8.count == 1
        }
        return (0x31...0x39).contains(first)
            && value.utf8.dropFirst().allSatisfy { (0x30...0x39).contains($0) }
    }
}
