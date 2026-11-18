//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension RecordingCSVReader {
    /// Bounds the bytes retained while reading a recording, independently of the caller's chunk size.
    public struct Limits: Sendable, Equatable {
        /// Limits that admit payloads up to the R4 attachment size, rows up to 4 MiB and fields up to 1 MiB.
        public static let `default` = Self()

        /// The most bytes of the complete payload.
        public let maximumByteCount: Int
        /// The most bytes of one encoded row, including its quotes, delimiters and terminator.
        public let maximumRecordByteCount: Int
        /// The most UTF-8 bytes of one decoded field.
        public let maximumFieldByteCount: Int

        /// Creates read limits, each between 1 and the R4 attachment size bound of `Int32.max` bytes.
        ///
        /// A reader refuses invalid limits when it is created, before it accepts any bytes.
        public init(
            maximumByteCount: Int = Int(Int32.max),
            maximumRecordByteCount: Int = 4 * 1024 * 1024,
            maximumFieldByteCount: Int = 1024 * 1024
        ) {
            self.maximumByteCount = maximumByteCount
            self.maximumRecordByteCount = maximumRecordByteCount
            self.maximumFieldByteCount = maximumFieldByteCount
        }

        func validate() throws(ReaderError) {
            guard (1...Int(Int32.max)).contains(maximumByteCount),
                  (1...Int(Int32.max)).contains(maximumRecordByteCount),
                  (1...Int(Int32.max)).contains(maximumFieldByteCount) else {
                throw .invalidReadLimits
            }
        }
    }

    /// Incrementally reads the same registered grammar as the whole-payload reader.
    ///
    /// Only the current row is retained. The consumer controls whether delivered rows are retained.
    /// Call ``finish()`` after the final chunk: a successful read alone does not prove that a payload
    /// is complete. Rows delivered before an error are provisional; consumers must not commit their
    /// effects until the complete payload is validated. Any error closes this stream.
    public struct Stream: Sendable {
        private enum Phase { case reading, finished, failed }

        /// The columns the format publishes, in order.
        public let columns: [String]
        private let schema: [RecordingCSVColumn]
        private var parser: RecordingCSVParser
        private var phase = Phase.reading

        /// Creates a stream that reads a payload as the given registry format.
        ///
        /// - Parameters:
        ///   - format: The registry format the carrying document declares.
        ///   - limits: The limits on the bytes the stream retains.
        public init(format: RegisteredRecordingFormat, limits: Limits = .default) throws(ReaderError) {
            guard let schema = format.csvSchema else {
                throw .notTabular(format)
            }
            let columns = schema.map(\.name)
            try limits.validate()
            self.columns = columns
            self.schema = schema
            self.parser = RecordingCSVParser(columns: columns, limits: limits)
        }

        /// Accepts a chunk, invoking `onRow` for each complete data row; the header is not delivered.
        public mutating func read(_ chunk: Data, onRow: (Row) throws -> Void) throws {
            guard phase == .reading else { throw ReaderError.streamClosed }
            do {
                let schema = schema
                try parser.read(chunk) { row in
                    for (column, value) in zip(schema, row.fields) where !column.admits(value) {
                        throw ReaderError.invalidColumnValue(column: column.name)
                    }
                    try onRow(row)
                }
            } catch {
                phase = .failed
                throw error
            }
        }

        /// Requires a complete final row and header. No more bytes may follow this call.
        public mutating func finish() throws(ReaderError) {
            guard phase == .reading else {
                throw .streamClosed
            }
            do {
                try parser.finish()
                phase = .finished
            } catch {
                phase = .failed
                throw error
            }
        }
    }
}
