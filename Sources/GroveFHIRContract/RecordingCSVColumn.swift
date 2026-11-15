//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A column's generated registry contract, shared by both recording writers and readers.
struct RecordingCSVColumn: Sendable {
    enum ValueType: Sendable { case string, integer, number, timestamp }
    let name: String
    let type: ValueType
    let nullable: Bool

    static func validateFields(_ fields: some Sequence<(RecordingCSVColumn, String)>) throws {
        for (column, value) in fields {
            try column.validate(value)
        }
    }

    private static func isInteger(_ value: Substring) -> Bool {
        let digits = value.first == "-" ? value.dropFirst() : value
        guard CanonicalNonnegativeDecimal.isCanonical(digits) else {
            return false
        }
        return value.first != "-" || digits != "0"
    }

    private static func isInteger(_ value: String) -> Bool {
        isInteger(value[...])
    }

    private static func isNumber(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
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
            guard !fraction.isEmpty, fraction.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  fraction.last != "0" || fraction == "0" else {
                return false
            }
        }
        guard let number = Double(value), number.isFinite else {
            return false
        }
        return whole.first != "-" || number != 0
    }

    func validate(_ value: String) throws {
        let valid: Bool
        if value.isEmpty {
            valid = nullable
        } else {
            switch type {
            case .string: valid = true
            case .integer: valid = Self.isInteger(value)
            case .number, .timestamp: valid = Self.isNumber(value)
            }
        }
        guard valid else { throw RecordingCSVReader.ReaderError.invalidColumnValue(column: name) }
    }
}
