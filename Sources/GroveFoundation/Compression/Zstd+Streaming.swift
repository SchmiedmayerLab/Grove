//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import libzstd


extension Zstd {
    /// Compresses a known-length input into one Zstandard frame without collecting the input or output.
    ///
    /// Feed source chunks to `write(_:to:)`, then call `finish(to:)` to emit the frame's remaining bytes.
    /// Output chunks are at most 64 KiB. Compression workspace depends on the selected level, rather
    /// than total input length. These synchronous operations belong on the caller's background executor.
    /// A consumer controls whether it retains chunks; a file sink keeps the pipeline bounded.
    ///
    /// Any error closes the stream. Discard its partial output and create a new compressor for a retry.
    public struct StreamCompressor: ~Copyable {
        /// A stream boundary, size, or lifecycle violation.
        public enum StreamError: Error, Equatable {
            case invalidByteCount
            case invalidWindowLimit
            case inputSizeMismatch
            case outputLimitExceeded
            case closed
        }

        private let context: OpaquePointer
        private let sourceByteCount: Int64
        private let maximumOutputByteCount: Int64
        private var inputByteCount: Int64 = 0
        /// The number of compressed bytes delivered to the output consumer.
        public private(set) var compressedByteCount: Int64 = 0
        private var finished = false
        private var buffer = Data(count: 64 * 1024)

        /// Creates one frame with an exact source size and a maximum compressed-output size.
        /// When supplied, the history window uses the largest power of two within the window budget.
        public init(
            sourceByteCount: Int64,
            maximumOutputByteCount: Int64,
            options: CompressionOptions = .init(),
            maximumWindowByteCount: Int? = nil
        ) throws {
            guard sourceByteCount >= 0, maximumOutputByteCount >= 0 else { throw StreamError.invalidByteCount }
            let windowLog: Int32?
            if let maximumWindowByteCount {
                guard maximumWindowByteCount > 0 else { throw StreamError.invalidWindowLimit }
                let value = Int32(Int.bitWidth - maximumWindowByteCount.leadingZeroBitCount - 1)
                let bounds = ZSTD_cParam_getBounds(ZSTD_c_windowLog)
                try Self.check(bounds.error)
                guard (bounds.lowerBound...bounds.upperBound).contains(value) else { throw StreamError.invalidWindowLimit }
                windowLog = value
            } else {
                windowLog = nil
            }
            try Task.checkCancellation()
            guard let context = ZSTD_createCCtx() else { throw CompressionError.notEnoughMemory }
            do {
                try Self.check(ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, options.level.rawValue))
                if let windowLog { try Self.check(ZSTD_CCtx_setParameter(context, ZSTD_c_windowLog, windowLog)) }
                try Self.check(ZSTD_CCtx_setPledgedSrcSize(context, UInt64(sourceByteCount)))
            } catch {
                ZSTD_freeCCtx(context)
                throw error
            }
            self.context = context
            self.sourceByteCount = sourceByteCount
            self.maximumOutputByteCount = maximumOutputByteCount
        }

        private static func check(_ result: Int) throws {
            guard ZSTD_isError(result) != 0 else {
                return
            }
            let code = ZSTD_getErrorCode(result)
            if code == ZSTD_error_memory_allocation { throw CompressionError.notEnoughMemory }
            throw CompressionError.other(code)
        }

        /// Consumes one input chunk. No output callback runs if the chunk exceeds the declared input size.
        public mutating func write(_ bytes: Data, to consume: (Data) throws -> Void) throws {
            guard !finished else { throw StreamError.closed }
            do {
                try Task.checkCancellation()
                guard Int64(bytes.count) <= sourceByteCount - inputByteCount else { throw StreamError.inputSizeMismatch }
                inputByteCount += Int64(bytes.count)
                try process(bytes, directive: ZSTD_e_continue, consume: consume)
            } catch {
                finished = true
                throw error
            }
        }

        /// Finishes exactly one frame; incomplete input cannot be finalized as a successful recording.
        public mutating func finish(to consume: (Data) throws -> Void) throws {
            guard !finished else { throw StreamError.closed }
            finished = true
            try Task.checkCancellation()
            guard inputByteCount == sourceByteCount else { throw StreamError.inputSizeMismatch }
            try process(Data(), directive: ZSTD_e_end, consume: consume)
        }

        private mutating func process(_ bytes: Data, directive: ZSTD_EndDirective, consume: (Data) throws -> Void) throws {
            let context = context
            try bytes.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
                while true {
                    try Task.checkCancellation()
                    let (remaining, written) = buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        let remaining = ZSTD_compressStream2(context, &output, &input, directive)
                        return (remaining, output.pos)
                    }
                    try Self.check(remaining)
                    guard Int64(written) <= maximumOutputByteCount - compressedByteCount else { throw StreamError.outputLimitExceeded }
                    if written > 0 {
                        compressedByteCount += Int64(written)
                        try consume(buffer.prefix(written))
                    }
                    try Task.checkCancellation()
                    if directive == ZSTD_e_end ? remaining == 0 : input.pos == input.size {
                        return
                    }
                }
            }
        }

        deinit { ZSTD_freeCCtx(context) }
    }
}
