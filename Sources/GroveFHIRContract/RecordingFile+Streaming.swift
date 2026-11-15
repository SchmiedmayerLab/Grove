//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension RecordingFile {
    /// Stages a complete byte stream in a privately owned, unnamed file. No partial file escapes
    /// on source failure, cancellation or capacity exhaustion. Writes and hashing use 64 KiB chunks;
    /// the source controls the size of the input chunk retained while it is being consumed.
    @concurrent
    public static func stage<Chunks: AsyncSequence & Sendable>(
        chunks: Chunks, maximumByteCount: Int64
    ) async throws -> Self where Chunks.Element: Collection & Sendable, Chunks.Element.Element == UInt8 {
        guard (1...Int64(Int32.max)).contains(maximumByteCount) else { throw FileError.invalidByteLimit }
        try Task.checkCancellation()
        let storage = try RecordingStaging.create()
        var count = 0
        var hasher = AttachmentHasher()
        for try await chunk in chunks {
            try Task.checkCancellation()
            guard chunk.count <= Int(maximumByteCount) - count else { throw FileError.byteLimitExceeded }
            var remaining = chunk[...]
            while !remaining.isEmpty {
                let bytes = Data(remaining.prefix(chunkByteCount))
                try write(bytes, to: storage.descriptor, offset: count)
                hasher.update(bytes)
                count += bytes.count
                remaining = remaining.dropFirst(bytes.count)
            }
        }
        try Task.checkCancellation()
        guard count > 0 else { throw FileError.emptySource }
        return Self(byteCount: count, attachmentSHA1: hasher.finalize(), storage: storage)
    }
}
