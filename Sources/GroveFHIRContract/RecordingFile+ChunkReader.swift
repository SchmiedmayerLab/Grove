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


extension RecordingFile {
    /// A bounded, independent position in an immutable recording snapshot.
    ///
    /// Copies share the file lifetime but keep separate read positions. Reads are synchronous
    /// disk operations and belong on the caller's background executor. No bytes are read ahead.
    public struct ChunkReader: Sendable {
        private let file: RecordingFile
        private var offset = 0

        init(file: RecordingFile) { self.file = file }

        /// Reads at most 64 KiB, or returns nil at the end. Cancellation never advances the position.
        /// Retaining a returned chunk does not affect subsequent reads or other readers.
        public mutating func readNextChunk() throws -> Data? {
            try Task.checkCancellation()
            guard offset < file.byteCount else {
                return nil
            }
            var bytes = Data(count: min(RecordingFile.chunkByteCount, file.byteCount - offset))
            let count = try bytes.withUnsafeMutableBytes { buffer in
                while true {
                    try Task.checkCancellation()
                    let count = pread(file.storage.descriptor, buffer.baseAddress, buffer.count, off_t(offset))
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw FileError.readFailed }
                    return count
                }
            }
            try Task.checkCancellation()
            bytes.removeSubrange(count..<bytes.count)
            offset += count
            return bytes
        }
    }
}
