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
import GroveFHIRContract


/// An immutable, privately owned snapshot of recording bytes, suitable for bounded reads.
///
/// Staging copies a regular source file; subsequent edits or removal of that source cannot change
/// this snapshot. Copies share ownership. The staged file has no filesystem name, and its final
/// owner closes it; the operating system also reclaims it if the process exits unexpectedly.
///
/// These synchronous disk operations belong on the caller's background executor. This temporary
/// snapshot is not a durable upload queue: copy its chunks into queue-owned storage before relying
/// on them across process launches. No caller file is removed or modified.
public struct RecordingFile: Sendable {
    public enum FileError: Error, Equatable, Sendable {
        case invalidByteLimit
        case sourceUnavailable
        case sourceNotRegular
        case emptySource
        case sourceChanged
        case byteLimitExceeded
        case stagingUnavailable
        case readFailed
        case writeFailed
    }

    struct CopiedBytes {
        let count: Int
        let hash: Data
    }

    /// The descriptor is never exposed publicly. `pread` gives each consumer its own offset.
    final class Storage: Sendable {
        let descriptor: Int32

        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { close(descriptor) }
    }

    static let chunkByteCount = 64 * 1024

    public let byteCount: Int
    let attachmentSHA1: Data
    let storage: Storage

    /// Copies at most the caller's limit, which must be between 1 and the R4 `Int32` attachment bound.
    ///
    /// The source is opened without following a final symlink and checked through that descriptor.
    /// Byte limits are checked while copying as well as before reading. Diagnostics contain no paths.
    public static func stage(copying sourceURL: URL, maximumByteCount: Int64) throws -> Self {
        guard (1...Int64(Int32.max)).contains(maximumByteCount) else { throw FileError.invalidByteLimit }
        try Task.checkCancellation()
        guard sourceURL.isFileURL, !sourceURL.path.utf8.contains(0) else { throw FileError.sourceUnavailable }
        let source = open(sourceURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { throw FileError.sourceUnavailable }
        defer { close(source) }
        var before = stat()
        guard fstat(source, &before) == 0 else { throw FileError.sourceUnavailable }
        guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw FileError.sourceNotRegular }
        guard before.st_size > 0 else { throw FileError.emptySource }
        guard before.st_size <= maximumByteCount else { throw FileError.byteLimitExceeded }
        let storage = try RecordingStaging.create()
        let copied = try copy(source: source, destination: storage.descriptor, expected: before, maximumByteCount: Int(maximumByteCount))
        return Self(byteCount: copied.count, attachmentSHA1: copied.hash, storage: storage)
    }

    static func copy(source: Int32, destination: Int32, expected: stat, maximumByteCount: Int) throws -> CopiedBytes {
        var buffer = Data(count: chunkByteCount)
        var count = 0
        var hasher = AttachmentHasher()
        while true {
            try Task.checkCancellation()
            let readCount = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, $0.count) }
            if readCount < 0, errno == EINTR { continue }
            guard readCount >= 0 else { throw FileError.readFailed }
            if readCount == 0 { break }
            guard readCount <= maximumByteCount - count else { throw FileError.byteLimitExceeded }
            let chunk = buffer.prefix(readCount)
            try write(chunk, to: destination, offset: count)
            hasher.update(chunk)
            count += readCount
        }
        var after = stat()
        guard fstat(source, &after) == 0, count == expected.st_size, unchanged(expected, after) else { throw FileError.sourceChanged }
        try Task.checkCancellation()
        return CopiedBytes(count: count, hash: hasher.finalize())
    }

    private static func write(_ bytes: Data, to descriptor: Int32, offset: Int) throws {
        try bytes.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                try Task.checkCancellation()
                let count = pwrite(descriptor, buffer.baseAddress?.advanced(by: written), buffer.count - written, off_t(offset + written))
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw FileError.writeFailed }
                written += count
            }
        }
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
    /// The format validator alone requests a whole payload, after applying its explicit decode limit.
    func decodedPayload(maximumByteCount: Int) throws -> Data {
        guard byteCount <= maximumByteCount else { throw FileError.byteLimitExceeded }
        var data = Data()
        data.reserveCapacity(byteCount)
        try readChunks { data.append($0) }
        return data
    }

    /// Reads chunks of at most 64 KiB without sharing a seek position with another consumer.
    ///
    /// The reader retains only its current chunk; consumers control whether they retain delivered
    /// chunks. Throwing or cancellation stops this reader and leaves the snapshot usable by others.
    public func readChunks(_ consume: (Data) throws -> Void) throws {
        try withExtendedLifetime(storage) {
            var offset = 0
            var buffer = Data(count: Self.chunkByteCount)
            while offset < byteCount {
                try Task.checkCancellation()
                let requested = min(buffer.count, byteCount - offset)
                let count = buffer.withUnsafeMutableBytes { bytes in
                    pread(storage.descriptor, bytes.baseAddress, requested, off_t(offset))
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw FileError.readFailed }
                try consume(buffer.prefix(count))
                offset += count
            }
            try Task.checkCancellation()
        }
    }
}
