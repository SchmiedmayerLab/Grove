//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


extension RecordingFile {
    /// Produces one Zstandard frame only when it is strictly smaller than this immutable source.
    /// Returns nil when the original should be sent unchanged. Either representation must fit the
    /// stored-byte budget; source reads, compression, cancellation and disk failures propagate.
    ///
    /// Both files remain temporary. Copy the selected file into durable queue storage before
    /// acknowledging collection. Memory is bounded by the compression window and fixed-size chunks;
    /// the caller must run these synchronous disk operations on a background executor.
    public func zstandardCompressedIfSmaller(
        maximumByteCount: Int,
        maximumWindowByteCount: Int = 8 * 1024 * 1024
    ) throws -> Self? {
        guard (1...Int(Int32.max)).contains(maximumByteCount) else { throw FileError.invalidByteLimit }
        var compressor = try Zstd.StreamCompressor(
            sourceByteCount: Int64(byteCount),
            maximumOutputByteCount: Int64(min(maximumByteCount, byteCount - 1)),
            maximumWindowByteCount: maximumWindowByteCount
        )
        let storage = try RecordingStaging.create()
        var written = 0
        var hasher = AttachmentHasher()
        func write(_ chunk: Data) throws {
            try Self.write(chunk, to: storage.descriptor, offset: written)
            hasher.update(chunk)
            written += chunk.count
        }
        do {
            var reader = makeChunkReader()
            while let chunk = try reader.readNextChunk() { try compressor.write(chunk, to: write) }
            try compressor.finish(to: write)
            try Task.checkCancellation()
            return Self(byteCount: written, attachmentSHA1: hasher.finalize(), storage: storage)
        } catch Zstd.StreamCompressor.StreamError.outputLimitExceeded {
            try Task.checkCancellation()
            guard byteCount <= maximumByteCount else { throw FileError.byteLimitExceeded }
            return nil
        }
    }
}
