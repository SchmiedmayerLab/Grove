//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Writes a registered CSV recording directly to an owned file with bounded working memory.
///
/// Uses the same field encoding as ``RecordingCSVWriter``. Only one bounded row and a 64 KiB
/// write buffer are retained, regardless of recording length. Disk operations are synchronous;
/// use the caller's background executor. An error or cancellation invalidates the writer, so a
/// failed recording cannot be finalized as a successful prefix. The resulting file is temporary;
/// durable upload queues must copy its chunks into their own storage.
public struct RecordingCSVFileWriter: ~Copyable {
    public enum FileWriterError: Error, Equatable, Sendable {
        case fieldLimitExceeded
        case recordLimitExceeded
        case payloadLimitExceeded
        case closed
    }

    private let columns: [String]
    private let schema: [RecordingCSVColumn]
    private let limits: RecordingCSVReader.Limits
    private var storage: RecordingFile.Storage?
    private var pending = Data()
    private var writtenByteCount = 0
    private var hasher = AttachmentHasher()

    /// Creates a recording with explicit total, encoded-row, and decoded-field byte budgets.
    /// The header counts toward these budgets. Invalid limits throw the reader's `invalidReadLimits` error.
    public init(format: RegisteredRecordingFormat, limits: RecordingCSVReader.Limits) throws {
        guard let columns = format.csvColumns else { throw RecordingCSVWriter.WriterError.notTabular(format) }
        try limits.validate()
        try Task.checkCancellation()
        let fields = columns.map(RecordingCSVWriter.Field.text)
        let count = try RecordingCSVRowEncoder.byteCount(fields, limits: limits)
        guard count <= limits.maximumByteCount else { throw FileWriterError.payloadLimitExceeded }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        RecordingCSVRowEncoder.append(fields, to: &bytes)
        let storage = try RecordingStaging.create()
        let header = Data(bytes)
        try RecordingFile.write(header, to: storage.descriptor, offset: 0)
        var hasher = AttachmentHasher()
        hasher.update(header)
        self.columns = columns
        self.schema = format.csvSchema ?? []
        self.limits = limits
        self.storage = storage
        self.writtenByteCount = header.count
        self.hasher = hasher
    }

    /// Creates a recording with the reader's default row and field budgets and the caller's total byte budget.
    public init(format: RegisteredRecordingFormat, maximumByteCount: Int) throws {
        try self.init(format: format, limits: RecordingCSVReader.Limits(
            maximumByteCount: maximumByteCount,
            maximumRecordByteCount: RecordingCSVReader.Limits.default.maximumRecordByteCount,
            maximumFieldByteCount: RecordingCSVReader.Limits.default.maximumFieldByteCount
        ))
    }

    /// Appends one sample in source order, checking limits before allocating its encoded row.
    public mutating func append(_ fields: [RecordingCSVWriter.Field]) throws {
        guard storage != nil else { throw FileWriterError.closed }
        do {
            try Task.checkCancellation()
            try RecordingCSVRowEncoder.validate(fields, columns: columns, schema: schema)
            let count = try RecordingCSVRowEncoder.byteCount(fields, limits: limits)
            guard count <= limits.maximumByteCount - writtenByteCount - pending.count else { throw FileWriterError.payloadLimitExceeded }
            var bytes: [UInt8] = []
            bytes.reserveCapacity(count)
            RecordingCSVRowEncoder.append(fields, to: &bytes)
            var offset = 0
            while offset < bytes.count {
                let chunkCount = min(bytes.count - offset, RecordingFile.chunkByteCount - pending.count)
                let end = offset + chunkCount
                pending.append(contentsOf: bytes[offset..<end])
                offset = end
                if pending.count == RecordingFile.chunkByteCount { try flush() }
            }
            try Task.checkCancellation()
        } catch {
            storage = nil
            pending.removeAll(keepingCapacity: false)
            throw error
        }
    }

    /// Finishes the complete recording and transfers immutable ownership without copying or rereading it.
    /// A header-only CSV is valid; clinical converters enforce any required sample count.
    public consuming func finish() throws -> RecordingFile {
        var writer = consume self
        guard let storage = writer.storage else { throw FileWriterError.closed }
        try writer.flush()
        try Task.checkCancellation()
        return RecordingFile(byteCount: writer.writtenByteCount, attachmentSHA1: writer.hasher.finalize(), storage: storage)
    }

    private mutating func flush() throws {
        guard let storage else { throw FileWriterError.closed }
        try RecordingFile.write(pending, to: storage.descriptor, offset: writtenByteCount)
        hasher.update(pending)
        writtenByteCount += pending.count
        pending.removeAll(keepingCapacity: true)
    }
}
