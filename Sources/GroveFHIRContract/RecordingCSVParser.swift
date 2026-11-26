//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The canonical byte grammar shared by whole-payload and incremental recording readers.
struct RecordingCSVParser: Sendable {
    typealias ReaderError = RecordingCSVReader.ReaderError
    private enum State { case fieldStart, unquoted, quoted, afterQuote }

    private let columns: [String]
    private let limits: RecordingCSVReader.Limits
    private var fields: [String] = []
    private var field: [UInt8] = []
    private var state = State.fieldStart
    private var row = 0
    private var byteOffset = 0
    private var recordByteCount = 0
    private var lastByte: UInt8?

    init(columns: [String], limits: RecordingCSVReader.Limits) {
        self.columns = columns
        self.limits = limits
    }

    /// Refuses a chunk that would take the payload past its byte limit.
    func admit(_ chunk: Data) throws(ReaderError) {
        guard chunk.count <= limits.maximumByteCount - byteOffset else { throw .payloadLimitExceeded }
    }

    /// Consumes one byte, returning the data row it completes; the header row is checked, not returned.
    mutating func consume(_ byte: UInt8) throws(ReaderError) -> RecordingCSVReader.Row? {
        guard recordByteCount < limits.maximumRecordByteCount else { throw .recordLimitExceeded(row: row) }
        recordByteCount += 1
        let completed = try read(byte)
        byteOffset += 1
        lastByte = byte
        return completed
    }

    func finish() throws(ReaderError) {
        guard byteOffset > 0 else { throw .missingHeader }
        // A scalar split across chunks is valid; an incomplete scalar at EOF is not.
        _ = try decodedField()
        guard lastByte == UInt8(ascii: "\n") else { throw .missingFinalRowTerminator }
        guard state != .quoted else { throw .unterminatedQuote(row: row) }
        guard row > 0 else { throw .missingHeader }
    }

    // Keep the four states beside one another so the registered quote grammar is directly auditable.
    // swiftlint:disable:next cyclomatic_complexity
    private mutating func read(_ byte: UInt8) throws(ReaderError) -> RecordingCSVReader.Row? {
        switch state {
        case .fieldStart:
            switch byte {
            case UInt8(ascii: "\""): state = .quoted
            case UInt8(ascii: ","): try appendField()
            case UInt8(ascii: "\n"): return try appendRow()
            case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
            default:
                try appendByte(byte)
                state = .unquoted
            }
        case .unquoted:
            switch byte {
            case UInt8(ascii: "\""): throw locationError(ReaderError.unexpectedQuote)
            case UInt8(ascii: ","): try appendField()
            case UInt8(ascii: "\n"): return try appendRow()
            case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
            default: try appendByte(byte)
            }
        case .quoted:
            switch byte {
            case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
            case UInt8(ascii: "\""): state = .afterQuote
            default: try appendByte(byte)
            }
        case .afterQuote:
            switch byte {
            case UInt8(ascii: "\""):
                try appendByte(byte)
                state = .quoted
            case UInt8(ascii: ","): try appendField()
            case UInt8(ascii: "\n"): return try appendRow()
            case UInt8(ascii: "\r"): throw locationError(ReaderError.unexpectedCarriageReturn)
            default: throw locationError(ReaderError.invalidCharacterAfterClosingQuote)
            }
        }
        return nil
    }

    private func locationError(_ error: (Int, Int, Int) -> ReaderError) -> ReaderError {
        error(row, fields.count, byteOffset)
    }

    private mutating func appendByte(_ byte: UInt8) throws(ReaderError) {
        guard field.count < limits.maximumFieldByteCount else {
            throw .fieldLimitExceeded(row: row, column: fields.count)
        }
        field.append(byte)
    }

    private func decodedField() throws(ReaderError) -> String {
        guard let value = String(bytes: field, encoding: .utf8) else { throw .invalidUTF8 }
        return value
    }

    private mutating func appendField() throws(ReaderError) {
        guard fields.count < columns.count else {
            throw .columnCountMismatch(row: row, expected: columns.count, actual: fields.count + 1)
        }
        let value = try decodedField()
        if state == .afterQuote, !RecordingCSVWriter.needsQuotes(value) {
            throw .unnecessaryQuotes(row: row, column: fields.count)
        }
        fields.append(value)
        field.removeAll(keepingCapacity: true)
        state = .fieldStart
    }

    private mutating func appendRow() throws(ReaderError) -> RecordingCSVReader.Row? {
        try appendField()
        defer {
            fields.removeAll(keepingCapacity: true)
            row += 1
            recordByteCount = 0
        }
        if row == 0 {
            guard fields == columns else { throw .unexpectedHeader(expected: columns, actual: fields) }
            return nil
        }
        guard fields.count == columns.count else {
            throw .columnCountMismatch(row: row, expected: columns.count, actual: fields.count)
        }
        return .init(fields: fields, columns: columns)
    }
}
