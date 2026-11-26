//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A column of a tabular recording format, as the recording-format registry declares it.
struct RecordingCSVColumn: Sendable {
    /// The value type the registry declares for a column.
    enum ValueType: Sendable {
        case string
        case integer
        case number
        case timestamp
    }

    let name: String
    let type: ValueType
    let nullable: Bool

    /// Whether `value` is a canonical base-ten integer: no sign for zero, no leading zeros and no plus sign.
    static func isInteger(_ value: String) -> Bool {
        let digits = value.first == "-" ? value.dropFirst() : value[...]
        return CanonicalNonnegativeDecimal.isCanonical(digits) && (value.first != "-" || digits != "0")
    }

    /// Whether `value` is a finite canonical decimal: an integer as ``isInteger(_:)`` defines it, optionally followed by a
    /// fraction without trailing zeros. A fraction of exactly `0` is admitted, and negative zero is not.
    static func isNumber(_ value: String) -> Bool {
        let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else {
            return false
        }
        let whole = parts[0]
        let unsigned = whole.first == "-" ? whole.dropFirst() : whole
        guard CanonicalNonnegativeDecimal.isCanonical(unsigned) else {
            return false
        }
        if parts.count == 2 {
            let fraction = parts[1]
            guard !fraction.isEmpty,
                  fraction.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  fraction.last != "0" || fraction == "0" else {
                return false
            }
        }
        guard let number = Double(value), number.isFinite else {
            return false
        }
        return whole.first != "-" || number != 0
    }

    /// Whether `value` is valid in this column: empty only in a nullable column, and otherwise of the column's type.
    func admits(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return nullable
        }
        return switch type {
        case .string: true
        case .integer: Self.isInteger(value)
        case .number, .timestamp: Self.isNumber(value)
        }
    }
}
