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
        /// Why ``read(_:onRow:)`` stopped: the payload, or the row consumer.
        public enum ReadFailure<Consumer: Error>: Error {
            /// The payload violates the registered grammar or the read limits, or the stream is closed.
            case reader(ReaderError)
            /// `onRow` threw this error.
            case consumer(Consumer)
        }

        private enum Phase { case reading, finished, failed }

        /// The columns the format publishes, in order.
        public let columns: [String]
        private let schema: [RecordingCSVColumn]
        private var parser: RecordingCSVParser
        private var phase = Phase.reading
        /// The one-based number of the next data row.
        private var nextRow = 1

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
        ///
        /// - Throws: ``ReadFailure/reader(_:)`` for the payload, ``ReadFailure/consumer(_:)`` with the error `onRow` throws.
        public mutating func read<Consumer: Error>(
            _ chunk: Data,
            onRow: (Row) throws(Consumer) -> Void
        ) throws(ReadFailure<Consumer>) {
            guard phase == .reading else { throw .reader(.streamClosed) }
            do {
                try parser.admit(chunk)
            } catch {
                phase = .failed
                throw .reader(error)
            }
            for byte in chunk {
                let row: Row?
                do {
                    row = try parser.consume(byte)
                    if let row {
                        try validate(row)
                    }
                } catch {
                    phase = .failed
                    throw .reader(error)
                }
                guard let row else { continue }
                do {
                    try onRow(row)
                } catch {
                    phase = .failed
                    throw .consumer(error)
                }
            }
        }

        /// Accepts a chunk and checks its rows without delivering them.
        public mutating func read(_ chunk: Data) throws(ReaderError) {
            do {
                try read(chunk) { (_: Row) in }
            } catch {
                switch error {
                case .reader(let error): throw error
                case .consumer(let never): switch never {}
                }
            }
        }

        /// ``read(_:onRow:)`` that appends every row to `rows`, so only reader errors remain.
        mutating func read(_ chunk: Data, appendingTo rows: inout [Row]) throws(ReaderError) {
            do {
                try read(chunk) { (row: Row) in rows.append(row) }
            } catch {
                switch error {
                case .reader(let error): throw error
                case .consumer(let never): switch never {}
                }
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


extension RecordingCSVReader.Stream.ReadFailure: Equatable where Consumer: Equatable {}


extension RecordingCSVReader.Stream {
    private mutating func validate(_ row: RecordingCSVReader.Row) throws(RecordingCSVReader.ReaderError) {
        for (column, value) in zip(schema, row.fields) where !column.admits(value) {
            throw .invalidColumnValue(row: nextRow, column: column.name)
        }
        nextRow += 1
    }
}
