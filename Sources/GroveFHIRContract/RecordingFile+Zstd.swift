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
    /// One Zstandard frame of the bytes, if it is strictly smaller than the bytes themselves.
    ///
    /// Returns `nil` when compression doesn't reduce the size, so the caller sends the snapshot unchanged. Reading,
    /// compression, disk errors and cancellation propagate. The frame is another temporary snapshot; copy it into
    /// durable storage before relying on it. Memory is bounded by the compression workspace and the 64 KiB chunks.
    public func zstandardCompressed() throws -> Self? {
        var compressor = try Zstd.StreamCompressor(sourceByteCount: byteCount, maximumCompressedByteCount: byteCount - 1)
        var builder = try Builder(maximumByteCount: byteCount)
        do {
            try readChunks { chunk in
                try compressor.write(chunk) { try builder.append($0) }
            }
            try compressor.finish { try builder.append($0) }
        } catch Zstd.StreamError.outputLimitExceeded {
            try Task.checkCancellation()
            return nil
        }
        return try builder.finish()
    }

    /// The bytes of the one complete Zstandard frame this snapshot holds, as a new snapshot.
    ///
    /// Apply a decompressed byte budget before calling this method. A truncated or damaged frame, trailing bytes, a
    /// decompressed size other than `decompressedByteCount` and a frame that needs a larger history window fail. A
    /// successful result establishes neither the format's validity nor any authorization.
    ///
    /// - Parameters:
    ///   - decompressedByteCount: The exact number of decompressed bytes, between 1 and `Int32.max`.
    ///   - maximumWindowByteCount: The largest history window the decoder allocates.
    public func zstandardDecompressed(decompressedByteCount: Int, maximumWindowByteCount: Int = 8 * 1024 * 1024) throws -> Self {
        var builder = try Builder(maximumByteCount: decompressedByteCount)
        var decompressor = try Zstd.StreamDecompressor(
            compressedByteCount: byteCount,
            decompressedByteCount: decompressedByteCount,
            maximumWindowByteCount: maximumWindowByteCount
        )
        try readChunks { chunk in
            try decompressor.write(chunk) { try builder.append($0) }
        }
        try decompressor.finish()
        return try builder.finish()
    }
}
