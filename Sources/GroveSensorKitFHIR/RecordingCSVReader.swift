//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Members are ordered to read as a narrative rather than by kind, and the parser mirrors the
// registry's quoting rules branch for branch rather than splitting them across helpers.
// swiftlint:disable type_contents_order cyclomatic_complexity

public import Foundation

/// Reads a tabular Grove recording payload back into its published columns.
///
/// The registry promises that a receiver can parse any admitted payload from the format code
/// alone. This is that promise executed: the code names the columns, the reader requires exactly
/// them, and a payload whose header disagrees is rejected rather than silently misread.
public struct RecordingCSVReader: Sendable {
    /// One parsed row, addressable by the column names the format publishes.
    public struct Row: Sendable, Equatable {
        /// The row's raw fields, in the format's column order.
        public let fields: [String]
        private let columns: [String]

        init(fields: [String], columns: [String]) {
            self.fields = fields
            self.columns = columns
        }

        /// The raw field under a published column name, or `nil` if the format has no such column.
        public subscript(column: String) -> String? {
            guard let index = columns.firstIndex(of: column) else {
                return nil
            }
            return fields[index]
        }

        /// Whether the column carries no value; the writer emits an empty field for an absent one.
        public func isAbsent(_ column: String) -> Bool {
            self[column]?.isEmpty ?? true
        }

        /// The column's value as a binary64 number, or `nil` when absent or not a number.
        public func number(_ column: String) -> Double? {
            guard let raw = self[column], !raw.isEmpty else {
                return nil
            }
            return Double(raw)
        }

        /// The column's value as an integer, or `nil` when absent or not an integer.
        public func integer(_ column: String) -> Int? {
            guard let raw = self[column], !raw.isEmpty else {
                return nil
            }
            return Int(raw)
        }

        /// The column's value as an instant; the registry writes timestamps as epoch seconds.
        public func timestamp(_ column: String) -> Date? {
            guard let seconds = number(column) else {
                return nil
            }
            return Date(timeIntervalSince1970: seconds)
        }
    }

    /// Why a payload could not be read as the format it claims to be.
    public enum ReaderError: Error, Equatable {
        /// The format publishes no column set, so it is not a tabular recording.
        case notTabular(RegisteredRecordingFormat)
        /// The payload is not the UTF-8 the registry requires.
        case invalidUTF8
        /// The payload carries no header row.
        case missingHeader
        /// The header names columns other than the ones the format publishes.
        case unexpectedHeader(expected: [String], actual: [String])
        /// A row carries a different number of fields than the header declares.
        case columnCountMismatch(row: Int, expected: Int, actual: Int)
        /// A quoted field is never closed.
        case unterminatedQuote(row: Int)
        /// The payload does not end with the row terminator the registry mandates.
        case missingFinalRowTerminator
    }

    /// The columns the format publishes, in order.
    public let columns: [String]
    /// Every data row, header excluded.
    public let rows: [Row]

    /// Reads a payload as the given registry format.
    ///
    /// - Parameters:
    ///   - data: The exact payload bytes.
    ///   - format: The registry format the carrying document declares.
    public init(_ data: Data, format: RegisteredRecordingFormat) throws {
        guard let expected = format.csvColumns else {
            throw ReaderError.notTabular(format)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReaderError.invalidUTF8
        }
        guard !text.isEmpty else {
            throw ReaderError.missingHeader
        }
        // The registry mandates LF after every row, the last one included; a truncated upload is
        // otherwise indistinguishable from a complete one whose final row happens to parse.
        guard text.hasSuffix("\n") else {
            throw ReaderError.missingFinalRowTerminator
        }
        var parsed = try Self.parse(text)
        guard !parsed.isEmpty else {
            throw ReaderError.missingHeader
        }
        let header = parsed.removeFirst()
        guard header == expected else {
            throw ReaderError.unexpectedHeader(expected: expected, actual: header)
        }
        for (offset, fields) in parsed.enumerated() where fields.count != expected.count {
            throw ReaderError.columnCountMismatch(
                row: offset + 1,
                expected: expected.count,
                actual: fields.count
            )
        }
        self.columns = expected
        self.rows = parsed.map { Row(fields: $0, columns: expected) }
    }

    /// Splits the payload into rows of fields.
    ///
    /// Parsed over unicode scalars in one pass rather than by splitting on newlines first: a
    /// quoted field may contain the row terminator, and splitting would tear such a row in half.
    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?

        while let scalar = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if scalar == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.unicodeScalars.append("\"")
                        } else {
                            quoted = false
                            pending = next
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty:
                quoted = true
            case ",":
                fields.append(field)
                field = ""
            case "\n":
                fields.append(field)
                rows.append(fields)
                fields = []
                field = ""
            case "\r":
                break
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if quoted {
            throw ReaderError.unterminatedQuote(row: rows.count)
        }
        return rows
    }
}
