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
    /// Decompresses exactly one Zstandard frame with bounded output chunks and a bounded decoder workspace.
    ///
    /// The caller declares both byte counts up front, for example from a transfer manifest, so the decompressor also
    /// accepts frames whose header doesn't state their decompressed size. The window budget bounds the decoder's history
    /// buffer independently of the decompressed size. The consumer receives chunks of at most 64 KiB, which stay
    /// provisional until ``finish()`` succeeds and the caller verifies their digest. These operations are synchronous and
    /// belong on a background executor.
    ///
    /// Any error closes the decompressor. Discard its partial output.
    public struct StreamDecompressor: ~Copyable {
        private let context: OpaquePointer
        private let compressedByteCount: Int
        private let decompressedByteCount: Int
        private var readByteCount = 0
        private var magic: UInt32 = 0
        private var magicByteCount = 0
        private var frameComplete = false
        private var closed = false
        private var buffer = Data(count: Zstd.streamChunkByteCount)
        /// The number of decompressed bytes delivered to the consumer, including provisional output before an error.
        public private(set) var writtenByteCount = 0

        /// Creates a decompressor for one frame.
        ///
        /// - Parameters:
        ///   - compressedByteCount: The exact number of compressed bytes, at least one.
        ///   - decompressedByteCount: The exact number of decompressed bytes.
        ///   - maximumWindowByteCount: The largest history window the decoder allocates. The effective window is the
        ///     largest power of two within this budget, and a frame that needs a larger window fails.
        public init(compressedByteCount: Int, decompressedByteCount: Int, maximumWindowByteCount: Int) throws(StreamError) {
            guard compressedByteCount > 0, decompressedByteCount >= 0 else {
                throw .invalidByteCount
            }
            guard maximumWindowByteCount > 0 else {
                throw .invalidWindowLimit
            }
            let bounds = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax)
            try Zstd.checkStream(bounds.error)
            let windowLog = Int32(Int.bitWidth - maximumWindowByteCount.leadingZeroBitCount - 1)
            guard (bounds.lowerBound...bounds.upperBound).contains(windowLog) else {
                throw .invalidWindowLimit
            }
            guard let context = ZSTD_createDCtx() else {
                throw .notEnoughMemory
            }
            do {
                try Zstd.checkStream(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, windowLog))
            } catch {
                ZSTD_freeDCtx(context)
                throw error
            }
            self.context = context
            self.compressedByteCount = compressedByteCount
            self.decompressedByteCount = decompressedByteCount
        }

        /// Decompresses one input chunk and delivers the decompressed bytes that are ready.
        ///
        /// Input beyond the declared compressed byte count is refused before decoding, and the consumer never receives
        /// more than the declared decompressed byte count.
        ///
        /// - Throws: A ``StreamError``, or the error `consume` throws.
        public mutating func write(_ bytes: Data, to consume: (Data) throws -> Void) throws {
            guard !closed else {
                throw StreamError.closed
            }
            do {
                guard bytes.count <= compressedByteCount - readByteCount else {
                    throw StreamError.inputSizeMismatch
                }
                if frameComplete, !bytes.isEmpty {
                    throw StreamError.trailingData
                }
                readByteCount += bytes.count
                try readMagic(bytes)
                if !bytes.isEmpty {
                    try process(bytes, consume: consume)
                }
            } catch {
                closed = true
                throw error
            }
        }

        /// Finishes decompression once the complete input formed exactly one frame of the declared decompressed size.
        public mutating func finish() throws(StreamError) {
            guard !closed else {
                throw .closed
            }
            closed = true
            guard readByteCount == compressedByteCount else {
                throw .inputSizeMismatch
            }
            guard frameComplete else {
                throw .truncatedFrame
            }
            guard writtenByteCount == decompressedByteCount else {
                throw .outputSizeMismatch
            }
        }

        /// Refuses anything but a Zstandard frame, including a skippable frame that would decode to an empty output.
        ///
        /// Each byte of the magic number is checked as it arrives, before the codec sees it, so a foreign input fails
        /// with ``StreamError/invalidFrame`` however it is split into chunks.
        private mutating func readMagic(_ bytes: Data) throws(StreamError) {
            for byte in bytes.prefix(MemoryLayout<UInt32>.size - magicByteCount) {
                magic |= UInt32(byte) << (magicByteCount * 8)
                magicByteCount += 1
            }
            let mask = magicByteCount == MemoryLayout<UInt32>.size ? UInt32.max : (UInt32(1) << (magicByteCount * 8)) - 1
            if magic != ZSTD_MAGICNUMBER & mask {
                throw .invalidFrame
            }
        }

        private mutating func process(_ bytes: Data, consume: (Data) throws -> Void) throws {
            let context = context
            try bytes.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
                while true {
                    let (remaining, written) = buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        let remaining = ZSTD_decompressStream(context, &output, &input)
                        return (remaining, output.pos)
                    }
                    try Zstd.checkStream(remaining)
                    guard written <= decompressedByteCount - writtenByteCount else {
                        throw StreamError.outputSizeMismatch
                    }
                    if remaining == 0 {
                        guard input.pos == input.size else {
                            throw StreamError.trailingData
                        }
                        frameComplete = true
                    }
                    if written > 0 {
                        writtenByteCount += written
                        try consume(buffer.prefix(written))
                    }
                    if frameComplete || (input.pos == input.size && written < buffer.count) {
                        return
                    }
                }
            }
        }

        deinit {
            ZSTD_freeDCtx(context)
        }
    }
}
