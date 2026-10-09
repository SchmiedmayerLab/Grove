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
        /// CR is prohibited everywhere in a registered tabular payload, including quoted fields.
        case carriageReturn(column: String)
        /// The registry publishes no column set for this format.
        case notTabular(RegisteredRecordingFormat)
    }

    private let columns: [String]
    private var bytes: [UInt8] = []

    /// Creates a writer for one closed column set, and writes the header row.
    public init(columns: [String]) {
        self.columns = columns
        appendRow(columns.map(Field.text))
    }

    /// Creates a writer for the exact column set the registry publishes for a tabular format.
    public init(format: RegisteredRecordingFormat) throws(WriterError) {
        guard let columns = format.csvColumns else {
            throw .notTabular(format)
        }
        self.init(columns: columns)
    }

    /// Appends one source sample, in source order.
    public mutating func append(_ fields: [Field]) throws {
        guard fields.count == columns.count else {
            throw WriterError.columnCountMismatch(expected: columns.count, actual: fields.count)
        }
        // Every field is checked before any is written, so a refused row leaves no partial line behind.
        for (column, field) in zip(columns, fields) {
            switch field {
            case .number(let value) where !value.isFinite:
                throw WriterError.nonFiniteNumber(column: column)
            case .timestamp(let date) where !date.timeIntervalSince1970.isFinite:
                throw WriterError.nonFiniteNumber(column: column)
            case .text(let value) where value.utf8.contains(0x0D):
                throw WriterError.carriageReturn(column: column)
            default:
                break
            }
        }
        appendRow(fields)
    }

    /// The complete payload.
    public consuming func data() -> Data {
        Data(bytes)
    }

    private mutating func appendRow(_ fields: [Field]) {
        for (index, field) in fields.enumerated() {
            if index > 0 {
                bytes.append(0x2C)
            }
            append(field)
        }
        bytes.append(0x0A)
    }

    private mutating func append(_ field: Field) {
        switch field {
        case .absent:
            break
        case .integer(let value):
            bytes.append(contentsOf: String(value).utf8)
        case .number(let value):
            bytes.append(contentsOf: Self.number(value).utf8)
        case .timestamp(let date):
            bytes.append(contentsOf: Self.number(date.timeIntervalSince1970).utf8)
        case .text(let value):
            // Quote exactly when the value contains a comma, a double quote, or LF. CR is rejected
            // before encoding because the registered grammar prohibits it even inside quotes.
            guard value.utf8.contains(where: { $0 == 0x2C || $0 == 0x22 || $0 == 0x0A }) else {
                bytes.append(contentsOf: value.utf8)
                return
            }
            bytes.append(0x22)
            if value.utf8.contains(0x22) {
                bytes.append(contentsOf: value.replacingOccurrences(of: "\"", with: "\"\"").utf8)
            } else {
                bytes.append(contentsOf: value.utf8)
            }
            bytes.append(0x22)
        }
    }

    /// The one locale-independent shortest round-trip algorithm shared by every Swift producer.
    private static func number(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }
}

// swiftlint:enable type_contents_order
