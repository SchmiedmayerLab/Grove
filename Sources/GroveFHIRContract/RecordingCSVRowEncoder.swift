//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// One canonical row encoder for in-memory and file-backed recording writers.
enum RecordingCSVRowEncoder {
    typealias Field = RecordingCSVWriter.Field
    typealias WriterError = RecordingCSVWriter.WriterError

    static func validate(_ fields: [Field], columns: [String], schema: [RecordingCSVColumn] = []) throws {
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
        try RecordingCSVColumn.validateFields(zip(schema, fields.lazy.map(string)))
    }

    /// Measures before allocating a row, including quoting, delimiters, and its final LF.
    static func byteCount(_ fields: [Field], limits: RecordingCSVReader.Limits) throws -> Int {
        var count = fields.count // one delimiter per field, with LF replacing the final comma
        guard count <= limits.maximumRecordByteCount else { throw RecordingCSVFileWriter.FileWriterError.recordLimitExceeded }
        for field in fields {
            let value = string(field)
            guard value.utf8.count <= limits.maximumFieldByteCount else { throw RecordingCSVFileWriter.FileWriterError.fieldLimitExceeded }
            let quoted = value.utf8.contains { $0 == 0x2C || $0 == 0x22 || $0 == 0x0A }
            let additions = [value.utf8.count, quoted ? 2 : 0, quoted ? value.utf8.count(where: { $0 == 0x22 }) : 0]
            for addition in additions {
                guard addition <= limits.maximumRecordByteCount - count else {
                    throw RecordingCSVFileWriter.FileWriterError.recordLimitExceeded
                }
                count += addition
            }
        }
        return count
    }

    private static func string(_ field: Field) -> String {
        switch field {
        case .absent: ""
        case .text(let value): value
        case .integer(let value): String(value)
        case .number(let value): number(value)
        case .timestamp(let value): number(value.timeIntervalSince1970)
        }
    }

    static func append(_ fields: [Field], to bytes: inout [UInt8]) {
        for (index, field) in fields.enumerated() {
            if index > 0 {
                bytes.append(0x2C)
            }
            append(field, to: &bytes)
        }
        bytes.append(0x0A)
    }

    private static func append(_ field: Field, to bytes: inout [UInt8]) {
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
            for byte in value.utf8 {
                bytes.append(byte)
                if byte == 0x22 { bytes.append(byte) }
            }
            bytes.append(0x22)
        }
    }

    /// The one locale-independent shortest round-trip algorithm shared by every Swift producer.
    private static func number(_ value: Double) -> String {
        String(groveFHIRPlainDecimal: value)
    }
}
