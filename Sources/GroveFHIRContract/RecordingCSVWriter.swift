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
        /// The registry publishes no column set for this format.
        case notTabular(RegisteredRecordingFormat)
        /// The row's field count does not match the declared column count.
        case columnCountMismatch(expected: Int, actual: Int)
        /// A number the registry's decimal form cannot represent.
        case nonFiniteNumber(column: String)
        /// CR is prohibited everywhere in a registered tabular payload, including quoted fields.
        case carriageReturn(column: String)
        /// A field violates its column's registered value type or absence rule.
        case invalidValue(column: String)
    }

    private let schema: [RecordingCSVColumn]
    private var bytes: [UInt8] = []

    /// Creates a writer for a tabular registry format, and writes the header row.
    ///
    /// The writer enforces the format's exact columns, value types and absence rules.
    public init(format: RegisteredRecordingFormat) throws(WriterError) {
        guard let schema = format.csvSchema else {
            throw .notTabular(format)
        }
        self.schema = schema
        Self.encode(schema.map { .text($0.name) }, into: &bytes)
    }

    /// Appends one source sample, in source order.
    ///
    /// Every field is checked before any is written, so a refused row leaves no partial line behind.
    public mutating func append(_ fields: [Field]) throws(WriterError) {
        try Self.validate(fields, schema: schema)
        Self.encode(fields, into: &bytes)
    }

    /// The complete payload.
    public consuming func data() -> Data {
        Data(bytes)
    }

    /// Checks that `fields` form one valid row of `schema`.
    static func validate(_ fields: [Field], schema: [RecordingCSVColumn]) throws(WriterError) {
        guard fields.count == schema.count else {
            throw .columnCountMismatch(expected: schema.count, actual: fields.count)
        }
        for (field, column) in zip(fields, schema) {
            switch field {
            case .number(let value) where !value.isFinite:
                throw .nonFiniteNumber(column: column.name)
            case .timestamp(let date) where !date.timeIntervalSince1970.isFinite:
                throw .nonFiniteNumber(column: column.name)
            case .text(let value) where value.utf8.contains(0x0D):
                throw .carriageReturn(column: column.name)
            default:
                break
            }
            guard column.admits(text(field)) else {
                throw .invalidValue(column: column.name)
            }
        }
    }

    /// Appends one encoded row of `fields`, terminated by LF, to `bytes`.
    static func encode(_ fields: [Field], into bytes: inout [UInt8]) {
        for (index, field) in fields.enumerated() {
            if index > 0 {
                bytes.append(0x2C)
            }
            let value = text(field)
            // Quote exactly when the value contains a comma, a double quote, or LF. CR is rejected
            // before encoding because the registered grammar prohibits it even inside quotes.
            guard needsQuotes(value) else {
                bytes.append(contentsOf: value.utf8)
                continue
            }
            bytes.append(0x22)
            for byte in value.utf8 {
                bytes.append(byte)
                if byte == 0x22 {
                    bytes.append(byte)
                }
            }
            bytes.append(0x22)
        }
        bytes.append(0x0A)
    }

    /// The unquoted text of a field.
    static func text(_ field: Field) -> String {
        switch field {
        case .absent: ""
        case .text(let value): value
        case .integer(let value): String(value)
        // The one locale-independent shortest round-trip algorithm shared by every Swift producer.
        case .number(let value): String(groveFHIRPlainDecimal: value)
        case .timestamp(let date): String(groveFHIRPlainDecimal: date.timeIntervalSince1970)
        }
    }

    /// Whether `value` contains a comma, a double quote or LF, so the registered grammar quotes it.
    static func needsQuotes(_ value: String) -> Bool {
        value.utf8.contains { $0 == 0x2C || $0 == 0x22 || $0 == 0x0A }
    }
}

// swiftlint:enable type_contents_order
