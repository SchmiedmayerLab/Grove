//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Members are ordered to read as a narrative rather than by kind, and the parser mirrors the
// registry's quoting rules branch for branch rather than splitting them across helpers.
// swiftlint:disable type_contents_order cyclomatic_complexity function_body_length

public import Foundation
public import GroveFHIRContract

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

        /// The column's value as a binary64 number, or `nil` only when the field is absent.
        ///
        /// An unknown column or malformed/non-finite value throws so corruption cannot be
        /// mistaken for a source that omitted the measurement.
        public func number(_ column: String) throws -> Double? {
            guard let raw = self[column] else {
                throw RowValueError.unknownColumn(column)
            }
            guard !raw.isEmpty else {
                return nil
            }
            guard Self.isPlainDecimal(raw), let value = Double(raw), value.isFinite else {
                throw RowValueError.malformedNumber(column: column, value: raw)
            }
            return value
        }

        /// Parses a required canonical binary64 field without conflating absence and corruption.
        public func requiredNumber(_ column: String) throws -> Double {
            guard let value = try number(column) else {
                throw RowValueError.absent(column)
            }
            return value
        }

        /// The column's value as an integer, or `nil` only when the field is absent.
        public func integer(_ column: String) throws -> Int? {
            guard let raw = self[column] else {
                throw RowValueError.unknownColumn(column)
            }
            guard !raw.isEmpty else {
                return nil
            }
            guard Self.isInteger(raw), let value = Int(raw) else {
                throw RowValueError.malformedInteger(column: column, value: raw)
            }
            return value
        }

        /// Parses a required base-ten integer field without conflating absence and corruption.
        public func requiredInteger(_ column: String) throws -> Int {
            guard let value = try integer(column) else {
                throw RowValueError.absent(column)
            }
            return value
        }

        /// The column's value as an instant; the registry writes timestamps as epoch seconds.
        public func timestamp(_ column: String) throws -> Date? {
            guard let seconds = try number(column) else {
                return nil
            }
            return Date(timeIntervalSince1970: seconds)
        }

        private static func isInteger(_ value: String) -> Bool {
            let digits = value.first == "-" ? value.dropFirst() : value[...]
            return !digits.isEmpty && digits.utf8.allSatisfy { (0x30...0x39).contains($0) }
        }

        /// Whether `value` is `-?[0-9]+(\.[0-9]+)?`, read in one pass over its bytes.
        private static func isPlainDecimal(_ value: String) -> Bool {
            var unsigned = value.utf8[...]
            if unsigned.first == 0x2D {
                unsigned = unsigned.dropFirst()
            }
            var integerDigits = 0
            var fractionDigits: Int?
            for byte in unsigned {
                switch byte {
                case 0x30...0x39 where fractionDigits == nil:
                    integerDigits += 1
                case 0x30...0x39:
                    fractionDigits? += 1
                case 0x2E where fractionDigits == nil:
                    fractionDigits = 0
                default:
                    return false
                }
            }
            return integerDigits > 0 && fractionDigits != 0
        }
    }

    public enum RowValueError: Error, Equatable, Sendable {
        case unknownColumn(String)
        case absent(String)
        case malformedNumber(column: String, value: String)
        case malformedInteger(column: String, value: String)
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
        /// A quote appeared inside an unquoted field.
        case unexpectedQuote(row: Int, column: Int, byteOffset: Int)
        /// Only a comma, LF, or end may follow a closing quote.
        case invalidCharacterAfterClosingQuote(row: Int, column: Int, byteOffset: Int)
        /// The registered canonical grammar prohibits CR everywhere, including quoted fields.
        case unexpectedCarriageReturn(row: Int, column: Int, byteOffset: Int)
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
        let parsed = try Self.parse(text)
        guard let header = parsed.first else {
            throw ReaderError.missingHeader
        }
        guard header == expected else {
            throw ReaderError.unexpectedHeader(expected: expected, actual: header)
        }
        let records = parsed.dropFirst()
        for (offset, fields) in records.enumerated() where fields.count != expected.count {
            throw ReaderError.columnCountMismatch(
                row: offset + 1,
                expected: expected.count,
                actual: fields.count
            )
        }
        self.columns = expected
        self.rows = records.map { Row(fields: $0, columns: expected) }
    }

    /// Splits the payload into rows of fields.
    ///
    /// Parsed in one pass rather than by splitting on newlines first: a quoted field may contain the row terminator,
    /// and splitting would tear such a row in half. The pass reads UTF-8 bytes: every byte the grammar gives meaning
    /// (quote, comma, LF, CR) is ASCII, which no byte of a multi-byte scalar equals, and each field becomes a String once.
    private static func parse(_ text: String) throws -> [[String]] {
        var text = text
        return try text.withUTF8 { try parse(utf8: $0) }
    }

    private static func parse(utf8 bytes: UnsafeBufferPointer<UInt8>) throws -> [[String]] {
        enum State {
            case fieldStart
            case unquoted
            case quoted
            case afterQuote
        }

        var rows: [[String]] = []
        var fields: [String] = []
        var field: [UInt8] = []
        var state = State.fieldStart
        var row = 0
        var byteOffset = 0

        func locationError(_ error: (Int, Int, Int) -> ReaderError) -> ReaderError {
            error(row, fields.count, byteOffset)
        }
        func appendField() {
            fields.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
            state = .fieldStart
        }
        func appendRow() {
            appendField()
            rows.append(fields)
            fields = []
            fields.reserveCapacity(rows[rows.count - 1].count)
            row += 1
        }

        while byteOffset < bytes.count {
            let byte = bytes[byteOffset]
            switch state {
            case .fieldStart:
                switch byte {
                case UInt8(ascii: "\""): state = .quoted
                case UInt8(ascii: ","): appendField()
                case UInt8(ascii: "\n"): appendRow()
                case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
                default:
                    field.append(byte)
                    state = .unquoted
                }
            case .unquoted:
                switch byte {
                case UInt8(ascii: "\""): throw locationError(ReaderError.unexpectedQuote)
                case UInt8(ascii: ","): appendField()
                case UInt8(ascii: "\n"): appendRow()
                case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
                default: field.append(byte)
                }
            case .quoted:
                switch byte {
                case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
                case UInt8(ascii: "\""): state = .afterQuote
                default: field.append(byte)
                }
            case .afterQuote:
                switch byte {
                case UInt8(ascii: "\""):
                    field.append(byte)
                    state = .quoted
                case UInt8(ascii: ","): appendField()
                case UInt8(ascii: "\n"): appendRow()
                case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
                default: throw locationError(ReaderError.invalidCharacterAfterClosingQuote)
                }
            }
            byteOffset += 1
        }
        if state == .quoted {
            throw ReaderError.unterminatedQuote(row: rows.count)
        }
        return rows
    }
}
