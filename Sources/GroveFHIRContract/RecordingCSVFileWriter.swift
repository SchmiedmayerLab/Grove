//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Writes a tabular registry format directly into a ``RecordingFile`` with bounded memory.
///
/// The file writer validates and encodes rows exactly as ``RecordingCSVWriter`` does, so both write the same bytes for
/// the same rows. It retains only the current row and a 64 KiB write buffer, however long the recording is, and it
/// computes the attachment checksum while writing. The disk operations are synchronous and belong on a background
/// executor.
///
/// Unlike ``RecordingCSVWriter``, which refuses an invalid row and stays usable, this writer closes on any error,
/// including a refused row, a file error or cancellation, so a failed recording can't be finished as a successful
/// prefix. Later calls throw ``RecordingCSVWriter/WriterError/closed``. The resulting file is a temporary snapshot;
/// copy its chunks into durable storage before relying on them.
public struct RecordingCSVFileWriter: ~Copyable {
    private let schema: [RecordingCSVColumn]
    private let limits: RecordingCSVReader.Limits
    private var builder: RecordingFile.Builder?

    /// Creates a writer for a tabular registry format, and writes the header row.
    ///
    /// The header counts toward the maximum byte count. Every row also stays within the row and field limits of
    /// ``RecordingCSVReader/Limits/default``, so the default reader reads every recording the writer finishes.
    ///
    /// - Parameters:
    ///   - format: The tabular registry format.
    ///   - maximumByteCount: The most bytes of the complete recording, between 1 and `Int32.max`.
    public init(format: RegisteredRecordingFormat, maximumByteCount: Int) throws {
        guard let schema = format.csvSchema else {
            throw RecordingCSVWriter.WriterError.notTabular(format)
        }
        let limits = RecordingCSVReader.Limits(maximumByteCount: maximumByteCount)
        var builder = try RecordingFile.Builder(maximumByteCount: maximumByteCount)
        try Self.append(schema.map { .text($0.name) }, limits: limits, to: &builder)
        self.schema = schema
        self.limits = limits
        self.builder = consume builder
    }

    /// Appends one source sample, in source order.
    ///
    /// Every field and the encoded size are checked before the row is allocated.
    ///
    /// - Throws: A ``RecordingCSVWriter/WriterError``, a ``RecordingFile/FileError`` or `CancellationError`.
    public mutating func append(_ fields: [RecordingCSVWriter.Field]) throws {
        guard var builder = builder.take() else {
            throw RecordingCSVWriter.WriterError.closed
        }
        try RecordingCSVWriter.validate(fields, schema: schema)
        try Self.append(fields, limits: limits, to: &builder)
        self.builder = consume builder
    }

    /// Finishes the recording and hands over its snapshot without copying or reading it again.
    ///
    /// A recording with only its header is valid; converters enforce any required sample count.
    public consuming func finish() throws -> RecordingFile {
        guard let builder = builder.take() else {
            throw RecordingCSVWriter.WriterError.closed
        }
        return try builder.finish()
    }
}


extension RecordingCSVFileWriter {
    fileprivate static func append(
        _ fields: [RecordingCSVWriter.Field],
        limits: RecordingCSVReader.Limits,
        to builder: inout RecordingFile.Builder
    ) throws {
        let count = try RecordingCSVWriter.encodedByteCount(fields, limits: limits)
        guard count <= limits.maximumByteCount - builder.byteCount else {
            throw RecordingCSVWriter.WriterError.payloadLimitExceeded
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        RecordingCSVWriter.encode(fields, into: &bytes)
        try builder.append(bytes)
    }
}
