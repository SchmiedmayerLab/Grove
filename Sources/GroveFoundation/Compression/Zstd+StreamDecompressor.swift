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
    /// Decodes exactly one Zstandard frame with bounded output chunks and decoder workspace.
    ///
    /// The caller declares both byte counts up front, for example from a transfer manifest. The window
    /// budget bounds the decoder's history buffer independently of the decoded size. Output remains
    /// provisional until ``finish()`` succeeds and the caller verifies its content digest.
    /// Any error closes this decoder; discard partial output. These synchronous operations belong
    /// on the caller's background executor.
    public struct StreamDecompressor: ~Copyable {
        /// A frame, stream boundary, size, or lifecycle violation.
        public enum StreamError: Error, Equatable {
            case invalidByteCount
            case invalidWindowLimit
            case invalidFrame
            case inputSizeMismatch
            case outputSizeMismatch
            case truncatedFrame
            case trailingData
            case closed
        }

        private let context: OpaquePointer
        private let compressedByteCount: Int64
        private let expectedDecodedByteCount: Int64
        private var inputByteCount: Int64 = 0
        /// Decoded bytes delivered to the consumer, including provisional output before a failure.
        public private(set) var decodedByteCount: Int64 = 0
        private var magic: UInt32 = 0
        private var magicByteCount = 0
        private var frameComplete = false
        private var closed = false
        private var buffer = Data(count: 64 * 1024)

        /// The effective history window is the largest power of two within `maximumWindowByteCount`.
        public init(compressedByteCount: Int64, decodedByteCount: Int64, maximumWindowByteCount: Int) throws {
            guard compressedByteCount > 0, decodedByteCount >= 0 else { throw StreamError.invalidByteCount }
            guard maximumWindowByteCount > 0 else { throw StreamError.invalidWindowLimit }
            let windowLog = Int32(Int.bitWidth - maximumWindowByteCount.leadingZeroBitCount - 1)
            let bounds = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax)
            try Self.check(bounds.error)
            guard (bounds.lowerBound...bounds.upperBound).contains(windowLog) else { throw StreamError.invalidWindowLimit }
            try Task.checkCancellation()
            guard let context = ZSTD_createDCtx() else { throw DecompressionError.notEnoughMemory }
            do {
                try Self.check(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, windowLog))
            } catch {
                ZSTD_freeDCtx(context)
                throw error
            }
            self.context = context
            self.compressedByteCount = compressedByteCount
            self.expectedDecodedByteCount = decodedByteCount
        }

        private static func check(_ result: Int) throws {
            guard ZSTD_isError(result) != 0 else {
                return
            }
            let code = ZSTD_getErrorCode(result)
            if code == ZSTD_error_memory_allocation { throw DecompressionError.notEnoughMemory }
            throw DecompressionError.other(code)
        }

        /// Refuses excess compressed input before decoding; delivered chunks never exceed the remaining decoded allowance.
        public mutating func write(_ bytes: Data, to consume: (Data) throws -> Void) throws {
            guard !closed else { throw StreamError.closed }
            do {
                try Task.checkCancellation()
                guard Int64(bytes.count) <= compressedByteCount - inputByteCount else { throw StreamError.inputSizeMismatch }
                if frameComplete, !bytes.isEmpty { throw StreamError.trailingData }
                inputByteCount += Int64(bytes.count)
                try readMagic(bytes)
                if !bytes.isEmpty { try process(bytes, consume: consume) }
                try Task.checkCancellation()
            } catch {
                closed = true
                throw error
            }
        }

        /// Requires complete input, a fully flushed single frame, and the exact declared decoded size.
        public mutating func finish() throws {
            guard !closed else { throw StreamError.closed }
            closed = true
            try Task.checkCancellation()
            guard inputByteCount == compressedByteCount else { throw StreamError.inputSizeMismatch }
            guard frameComplete else { throw StreamError.truncatedFrame }
            guard decodedByteCount == expectedDecodedByteCount else { throw StreamError.outputSizeMismatch }
        }

        /// Rejects anything but a Zstandard frame, including a skippable frame that would decode to an allowed empty output.
        private mutating func readMagic(_ bytes: Data) throws {
            for byte in bytes.prefix(MemoryLayout<UInt32>.size - magicByteCount) {
                magic |= UInt32(byte) << (magicByteCount * 8)
                magicByteCount += 1
            }
            if magicByteCount == MemoryLayout<UInt32>.size, magic != ZSTD_MAGICNUMBER { throw StreamError.invalidFrame }
        }

        private mutating func process(_ bytes: Data, consume: (Data) throws -> Void) throws {
            let context = context
            try bytes.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
                while true {
                    try Task.checkCancellation()
                    let (remaining, written) = buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        let remaining = ZSTD_decompressStream(context, &output, &input)
                        return (remaining, output.pos)
                    }
                    try Self.check(remaining)
                    guard Int64(written) <= expectedDecodedByteCount - decodedByteCount else { throw StreamError.outputSizeMismatch }
                    if remaining == 0 {
                        guard input.pos == input.size else { throw StreamError.trailingData }
                        frameComplete = true
                    }
                    if written > 0 {
                        decodedByteCount += Int64(written)
                        try consume(buffer.prefix(written))
                    }
                    try Task.checkCancellation()
                    if frameComplete || (input.pos == input.size && written < buffer.count) {
                        return
                    }
                }
            }
        }

        deinit { ZSTD_freeDCtx(context) }
    }
}
