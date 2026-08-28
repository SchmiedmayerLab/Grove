//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Members are ordered to read as a narrative rather than by kind.
// swiftlint:disable type_contents_order

public import Foundation


/// Writes the tabular recording formats the registry publishes.
///
/// The registry specifies each format to the byte — UTF-8 without a byte-order mark, LF after every
/// row including the last, comma separated, and a closed column set declared per stream. Grove ships
/// the writer so that a producer conforms by construction rather than by re-reading the
/// specification: two adopters hand-writing it is two chances to disagree about quoting.
public struct RecordingCSVWriter: ~Copyable {
    /// A value a CSV column can carry.
    public enum Field: Sendable, Equatable {
        case text(String)
        case number(Double)
        case integer(Int)
        /// Seconds since the Unix epoch, written in the registry's number form.
        case timestamp(Date)
        /// A column the source did not report. Written as an empty, unquoted field.
        case absent
    }

    /// An error from writing a row.
    public enum WriterError: Error, Equatable {
        /// The row's field count does not match the declared column count.
        case columnCountMismatch(expected: Int, actual: Int)
        /// A number the registry's decimal form cannot represent.
        case nonFiniteNumber(column: String)
    }

    private let columns: [String]
    private var bytes: Data

    /// Creates a writer for one closed column set, and writes the header row.
    public init(columns: [String]) {
        self.columns = columns
        self.bytes = Data()
        appendRow(columns.map { Self.encode(.text($0)) })
    }

    /// Appends one source sample, in source order.
    public mutating func append(_ fields: [Field]) throws {
        guard fields.count == columns.count else {
            throw WriterError.columnCountMismatch(expected: columns.count, actual: fields.count)
        }
        var encoded: [String] = []
        encoded.reserveCapacity(fields.count)
        for (column, field) in zip(columns, fields) {
            switch field {
            case .number(let value) where !value.isFinite:
                throw WriterError.nonFiniteNumber(column: column)
            case .timestamp(let date) where !date.timeIntervalSince1970.isFinite:
                throw WriterError.nonFiniteNumber(column: column)
            default:
                break
            }
            encoded.append(Self.encode(field))
        }
        appendRow(encoded)
    }

    /// The complete payload.
    public consuming func data() -> Data {
        bytes
    }

    private mutating func appendRow(_ encoded: [String]) {
        bytes.append(contentsOf: Array(encoded.joined(separator: ",").utf8))
        bytes.append(0x0A)
    }

    private static func encode(_ field: Field) -> String {
        switch field {
        case .absent:
            return ""
        case .integer(let value):
            return String(value)
        case .number(let value):
            return number(value)
        case .timestamp(let date):
            return number(date.timeIntervalSince1970)
        case .text(let value):
            // Quote exactly when the value contains a comma, a double quote, or a line break.
            // Tested over unicode scalars rather than characters: Swift treats CRLF as one
            // Character that equals neither "\n" nor "\r", so a character-wise test misses it and
            // writes a raw line break that splits the row.
            let needsQuoting = value.unicodeScalars.contains { scalar in
                scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
            }
            guard needsQuoting else {
                return value
            }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }

    /// The one locale-independent shortest round-trip algorithm shared by every Swift producer.
    private static func number(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }
}

// swiftlint:enable type_contents_order
