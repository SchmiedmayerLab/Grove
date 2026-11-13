//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


extension RecordingCSVReader {
    /// Bounds the bytes retained while reading a recording, independently of the caller's chunk size.
    public struct Limits: Sendable, Equatable {
        /// Defaults admit R4-sized payloads, rows up to 4 MiB, and decoded fields up to 1 MiB.
        public static let `default` = Self(
            maximumByteCount: Int(Int32.max),
            maximumRecordByteCount: 4 * 1024 * 1024,
            maximumFieldByteCount: 1024 * 1024
        )

        public let maximumByteCount: Int
        public let maximumRecordByteCount: Int
        public let maximumFieldByteCount: Int

        /// Invalid limits are refused when a reader is created, before accepting any bytes.
        public init(maximumByteCount: Int, maximumRecordByteCount: Int, maximumFieldByteCount: Int) {
            self.maximumByteCount = maximumByteCount
            self.maximumRecordByteCount = maximumRecordByteCount
            self.maximumFieldByteCount = maximumFieldByteCount
        }

        func validate() throws {
            guard (1...Int(Int32.max)).contains(maximumByteCount),
                  (1...Int(Int32.max)).contains(maximumRecordByteCount),
                  (1...Int(Int32.max)).contains(maximumFieldByteCount) else {
                throw ReaderError.invalidReadLimits
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

        public let columns: [String]
        private var parser: RecordingCSVParser
        private var phase = Phase.reading

        public init(format: RegisteredRecordingFormat, limits: Limits = .default) throws {
            guard let columns = format.csvColumns else { throw ReaderError.notTabular(format) }
            try limits.validate()
            self.columns = columns
            self.parser = RecordingCSVParser(columns: columns, limits: limits)
        }

        /// Accepts a chunk, invoking `onRow` for each complete data row; the header is not delivered.
        public mutating func read(_ chunk: Data, onRow: (Row) throws -> Void) throws {
            guard phase == .reading else { throw ReaderError.streamClosed }
            do {
                try parser.read(chunk, onRow: onRow)
            } catch {
                phase = .failed
                throw error
            }
        }

        /// Requires a complete final row and header. No more bytes may follow this call.
        public mutating func finish() throws {
            guard phase == .reading else { throw ReaderError.streamClosed }
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
