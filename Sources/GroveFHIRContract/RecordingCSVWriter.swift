//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

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
        RecordingCSVRowEncoder.append(columns.map(Field.text), to: &bytes)
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
        try RecordingCSVRowEncoder.validate(fields, columns: columns)
        RecordingCSVRowEncoder.append(fields, to: &bytes)
    }

    /// The complete payload.
    public consuming func data() -> Data {
        Data(bytes)
    }
}
