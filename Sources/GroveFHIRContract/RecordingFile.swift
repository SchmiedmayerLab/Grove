//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
public import Foundation


/// An immutable, privately owned snapshot of recording bytes, read in bounded chunks.
///
/// Staging copies or writes the bytes into a temporary file that has no filesystem name, so later edits or removal of
/// a source file cannot change the snapshot. Copies of a `RecordingFile` share the snapshot, which closes with its last
/// owner; the operating system also reclaims it if the process exits. No caller file is removed or modified.
///
/// The disk operations are synchronous and belong on a background executor. The snapshot is temporary, not a durable
/// upload queue: copy its chunks into storage the queue owns before relying on them across process launches.
public struct RecordingFile: Sendable {
    /// Why a recording file could not be staged or read.
    public enum FileError: Error, Equatable, Sendable {
        /// A maximum byte count is outside 1 through the R4 attachment size bound of `Int32.max` bytes.
        case invalidByteLimit
        /// The source file doesn't exist, can't be opened, or is a symbolic link.
        case sourceUnavailable
        /// The source is not a regular file.
        case sourceNotRegular
        /// The source holds no bytes.
        case emptySource
        /// The source changed while it was copied.
        case sourceChanged
        /// The bytes exceed the maximum byte count.
        case byteLimitExceeded
        /// No temporary file could be created.
        case stagingUnavailable
        /// Reading failed.
        case readFailed
        /// Writing failed.
        case writeFailed
    }

    /// Owns the descriptor of the unnamed file. `pread` gives each reader its own position.
    final class Storage: Sendable {
        let descriptor: Int32

        init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit {
            close(descriptor)
        }
    }

    /// The largest chunk a recording file reads or writes at once.
    static let chunkByteCount = 64 * 1024

    /// The number of bytes in the snapshot.
    public let byteCount: Int
    /// The SHA-1 digest FHIR R4 `Attachment.hash` states for the bytes.
    package let attachmentSHA1: Data
    let storage: Storage

    /// The bytes in chunks of at most 64 KiB, read from the snapshot only when the sequence requests the next chunk.
    ///
    /// Every iterator retains the snapshot and has its own position.
    public var chunks: Chunks {
        Chunks(file: self)
    }

    /// Copies a regular file into a new snapshot.
    ///
    /// The source is opened without following a final symbolic link and checked through that descriptor. The byte limit
    /// is checked before and while copying, and diagnostics contain no paths.
    ///
    /// - Parameters:
    ///   - sourceURL: The file URL of the source.
    ///   - maximumByteCount: The most bytes the source may hold, between 1 and `Int32.max`.
    public static func stage(copying sourceURL: URL, maximumByteCount: Int) throws -> Self {
        try validate(maximumByteCount: maximumByteCount)
        guard sourceURL.isFileURL, !sourceURL.path.utf8.contains(0) else {
            throw FileError.sourceUnavailable
        }
        let source = open(sourceURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else {
            throw FileError.sourceUnavailable
        }
        defer {
            close(source)
        }
        var before = stat()
        guard fstat(source, &before) == 0 else {
            throw FileError.sourceUnavailable
        }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw FileError.sourceNotRegular
        }
        guard before.st_size > 0 else {
            throw FileError.emptySource
        }
        guard before.st_size <= maximumByteCount else {
            throw FileError.byteLimitExceeded
        }
        return try copy(from: source, expected: before, maximumByteCount: maximumByteCount)
    }

    /// Stages a complete byte stream in a new snapshot.
    ///
    /// No partial snapshot escapes when the stream fails, the task is cancelled or the bytes exceed the limit. The
    /// snapshot is written in chunks of at most 64 KiB; the stream controls the size of the chunk retained while it is
    /// consumed.
    ///
    /// - Parameters:
    ///   - chunks: The bytes, in order.
    ///   - maximumByteCount: The most bytes the stream may deliver, between 1 and `Int32.max`.
    @concurrent
    public static func stage<Bytes: AsyncSequence & Sendable>(
        chunks: Bytes,
        maximumByteCount: Int
    ) async throws -> Self where Bytes.Element: Collection<UInt8> & Sendable {
        var builder = try Builder(maximumByteCount: maximumByteCount)
        for try await chunk in chunks {
            try builder.append(chunk)
        }
        return try builder.finish()
    }

    /// Stages the bytes `body` produces synchronously, written in chunks of at most 64 KiB.
    ///
    /// An error `body` throws or an exceeded byte limit discards the file instead of returning a partial snapshot, and
    /// `append` refuses every further byte after its first failure.
    package static func stage(
        maximumByteCount: Int,
        producing body: (_ append: (Data) throws -> Void) throws -> Void
    ) throws -> Self {
        var builder = try Builder(maximumByteCount: maximumByteCount)
        var failure: (any Error)?
        try body { bytes in
            if let failure {
                throw failure
            }
            do {
                try builder.append(bytes)
            } catch {
                failure = error
                throw error
            }
        }
        if let failure {
            throw failure
        }
        return try builder.finish()
    }

    /// Reads the bytes in chunks of at most 64 KiB, independently of any other reader.
    ///
    /// Only the current chunk is retained; `consume` controls whether it retains delivered chunks. An error or
    /// cancellation stops this read and leaves the snapshot usable by others.
    public func readChunks(_ consume: (Data) throws -> Void) throws {
        var reader = ChunkReader(file: self)
        while let chunk = try reader.readNextChunk() {
            try consume(chunk)
        }
    }

    /// The complete bytes, for a validator that needs the whole payload within an explicit decoding limit.
    package func decodedPayload(maximumByteCount: Int) throws -> Data {
        guard byteCount <= maximumByteCount else {
            throw FileError.byteLimitExceeded
        }
        var data = Data()
        data.reserveCapacity(byteCount)
        try readChunks { data.append($0) }
        return data
    }
}


extension RecordingFile {
    /// The chunks of a recording file as an asynchronous sequence.
    public struct Chunks: AsyncSequence, Sendable {
        /// Reads the next chunk of a recording file when it is requested.
        public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
            private var reader: ChunkReader

            init(file: RecordingFile) {
                reader = ChunkReader(file: file)
            }

            /// The next chunk of at most 64 KiB, or `nil` at the end.
            public mutating func next() async throws -> Data? {
                try reader.readNextChunk()
            }
        }

        private let file: RecordingFile

        init(file: RecordingFile) {
            self.file = file
        }

        /// Creates an iterator with its own position in the snapshot.
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(file: file)
        }
    }

    /// A position in a snapshot that reads one bounded chunk at a time and never reads ahead.
    struct ChunkReader: Sendable {
        private let file: RecordingFile
        private var offset = 0

        init(file: RecordingFile) {
            self.file = file
        }

        /// Reads at most 64 KiB, or returns `nil` at the end. Cancellation never advances the position.
        mutating func readNextChunk() throws -> Data? {
            try Task.checkCancellation()
            guard offset < file.byteCount else {
                return nil
            }
            var bytes = Data(count: min(RecordingFile.chunkByteCount, file.byteCount - offset))
            let count = try bytes.withUnsafeMutableBytes { buffer in
                while true {
                    let count = pread(file.storage.descriptor, buffer.baseAddress, buffer.count, off_t(offset))
                    if count < 0, errno == EINTR {
                        continue
                    }
                    guard count > 0 else {
                        throw FileError.readFailed
                    }
                    return count
                }
            }
            bytes.removeSubrange(count..<bytes.count)
            offset += count
            return bytes
        }
    }

    /// Writes, hashes and counts the bytes of a new snapshot in chunks of at most 64 KiB.
    ///
    /// The file is unnamed before the first byte is written. A builder that is not finished closes its file, so a
    /// failure never exposes a partial snapshot.
    struct Builder: ~Copyable {
        private let storage: Storage
        private let maximumByteCount: Int
        private var pending = Data()
        private var writtenByteCount = 0
        private var hasher = AttachmentHasher()

        /// The number of bytes appended so far.
        var byteCount: Int {
            writtenByteCount + pending.count
        }

        /// Creates the unnamed file of a new snapshot of at most `maximumByteCount` bytes.
        init(maximumByteCount: Int) throws {
            try RecordingFile.validate(maximumByteCount: maximumByteCount)
            try Task.checkCancellation()
            self.storage = try Self.createUnnamedFile()
            self.maximumByteCount = maximumByteCount
        }

        /// Appends `bytes`, refusing them as a whole if they would exceed the maximum byte count.
        mutating func append(_ bytes: some Collection<UInt8>) throws {
            try Task.checkCancellation()
            guard bytes.count <= maximumByteCount - byteCount else {
                throw FileError.byteLimitExceeded
            }
            var remaining = bytes[...]
            while !remaining.isEmpty {
                let prefix = remaining.prefix(RecordingFile.chunkByteCount - pending.count)
                pending.append(contentsOf: prefix)
                remaining = remaining.dropFirst(prefix.count)
                if pending.count == RecordingFile.chunkByteCount {
                    try flush()
                }
            }
        }

        /// Writes the remaining bytes and returns the snapshot.
        ///
        /// - Parameter allowingEmpty: Whether a snapshot without bytes is valid; otherwise it fails with
        ///   ``FileError/emptySource``.
        consuming func finish(allowingEmpty: Bool = false) throws -> RecordingFile {
            try flush()
            try Task.checkCancellation()
            guard allowingEmpty || writtenByteCount > 0 else {
                throw FileError.emptySource
            }
            return RecordingFile(byteCount: writtenByteCount, attachmentSHA1: hasher.finalize(), storage: storage)
        }

        private mutating func flush() throws {
            try pending.withUnsafeBytes { buffer in
                var written = 0
                while written < buffer.count {
                    let count = pwrite(
                        storage.descriptor,
                        buffer.baseAddress?.advanced(by: written),
                        buffer.count - written,
                        off_t(writtenByteCount + written)
                    )
                    if count < 0, errno == EINTR {
                        continue
                    }
                    guard count > 0 else {
                        throw FileError.writeFailed
                    }
                    written += count
                }
            }
            hasher.update(pending)
            writtenByteCount += pending.count
            pending.removeAll(keepingCapacity: true)
        }
    }
}


extension RecordingFile {
    /// Refuses a maximum byte count outside 1 through the R4 attachment size bound.
    static func validate(maximumByteCount: Int) throws(FileError) {
        guard (1...Int(Int32.max)).contains(maximumByteCount) else {
            throw .invalidByteLimit
        }
    }

    /// Copies the open regular file `source` into a new snapshot, refusing it if it no longer matches `expected`.
    static func copy(from source: Int32, expected: stat, maximumByteCount: Int) throws -> Self {
        var builder = try Builder(maximumByteCount: maximumByteCount)
        var buffer = Data(count: chunkByteCount)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, $0.count) }
            if readCount < 0, errno == EINTR {
                continue
            }
            guard readCount >= 0 else {
                throw FileError.readFailed
            }
            guard readCount > 0 else {
                break
            }
            try builder.append(buffer.prefix(readCount))
        }
        var after = stat()
        guard fstat(source, &after) == 0, builder.byteCount == expected.st_size, unchanged(expected, after) else {
            throw FileError.sourceChanged
        }
        return try builder.finish()
    }

    private static func unchanged(_ before: stat, _ after: stat) -> Bool {
        #if canImport(Darwin)
        before.st_size == after.st_size
            && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
            && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        #else
        before.st_size == after.st_size
            && before.st_mtim.tv_sec == after.st_mtim.tv_sec && before.st_mtim.tv_nsec == after.st_mtim.tv_nsec
            && before.st_ctim.tv_sec == after.st_ctim.tv_sec && before.st_ctim.tv_nsec == after.st_ctim.tv_nsec
        #endif
    }
}


extension RecordingFile.Builder {
    /// Creates a file in the temporary directory and removes its name before any byte is written, so an
    /// interrupted process can leave behind only an empty file.
    fileprivate static func createUnnamedFile() throws(RecordingFile.FileError) -> RecordingFile.Storage {
        let template = FileManager.default.temporaryDirectory.appendingPathComponent("grove-recording-XXXXXX").path
        var path = Array(template.utf8CString)
        let descriptor = path.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            #if canImport(Darwin)
            return mkostemp(baseAddress, O_CLOEXEC)
            #else
            let descriptor = mkstemp(baseAddress)
            if descriptor >= 0 {
                _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            }
            return descriptor
            #endif
        }
        guard descriptor >= 0 else {
            throw .stagingUnavailable
        }
        let storage = RecordingFile.Storage(descriptor: descriptor)
        guard unlink(path) == 0 else {
            throw .stagingUnavailable
        }
        return storage
    }
}
