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
    /// Decodes one complete Zstandard frame into an immutable file with exactly the declared size.
    /// The caller applies its decoded-byte budget before supplying `byteCount`. Trailing bytes,
    /// incomplete frames, size mismatches and windows exceeding the memory budget fail explicitly.
    /// Run these synchronous disk operations on a background executor.
    public func zstandardDecompressed(
        byteCount: Int, maximumWindowByteCount: Int = 8 * 1024 * 1024
    ) throws -> Self {
        guard (1...Int(Int32.max)).contains(byteCount) else { throw FileError.invalidByteLimit }
        try Task.checkCancellation()
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(self.byteCount), decodedByteCount: Int64(byteCount), maximumWindowByteCount: maximumWindowByteCount
        )
        let storage = try RecordingStaging.create()
        var written = 0
        var hasher = AttachmentHasher()
        var reader = makeChunkReader()
        while let chunk = try reader.readNextChunk() {
            try decoder.write(chunk) { bytes in
                try Self.write(bytes, to: storage.descriptor, offset: written)
                hasher.update(bytes)
                written += bytes.count
            }
        }
        try decoder.finish()
        try Task.checkCancellation()
        return Self(byteCount: written, attachmentSHA1: hasher.finalize(), storage: storage)
    }
}
