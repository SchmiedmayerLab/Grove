//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import libzstd


extension Zstd {
    /// Why a ``StreamCompressor`` or ``StreamDecompressor`` refused its configuration or closed.
    ///
    /// Any error closes the stream. Discard its partial output and create a new stream for a retry.
    public enum StreamError: Error, Sendable, Equatable {
        /// A declared byte count is negative, or a decompressor's compressed byte count is zero.
        case invalidByteCount
        /// The history window budget is outside the range Zstandard supports.
        case invalidWindowLimit
        /// The input is not a Zstandard frame. A skippable frame is refused as well.
        case invalidFrame
        /// The written input differs from the declared input byte count.
        case inputSizeMismatch
        /// The compressed output would exceed the compressor's maximum compressed byte count.
        case outputLimitExceeded
        /// The decompressed output differs from the declared decompressed byte count.
        case outputSizeMismatch
        /// The input ended before the frame did.
        case truncatedFrame
        /// Bytes follow the frame, such as a second frame.
        case trailingData
        /// The stream was finished or closed by an earlier error.
        case closed
        /// Zstandard could not allocate its workspace.
        case notEnoughMemory
        /// Zstandard reported an error, such as a damaged frame or a failed checksum.
        case codec(ZSTD_ErrorCode)
    }

    /// The largest chunk a stream delivers to its consumer.
    static let streamChunkByteCount = 64 * 1024

    static func checkStream(_ result: Int) throws(StreamError) {
        guard ZSTD_isError(result) != 0 else {
            return
        }
        let code = ZSTD_getErrorCode(result)
        throw code == ZSTD_error_memory_allocation ? .notEnoughMemory : .codec(code)
    }
}
