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
    /// Compresses an input of known length into one Zstandard frame without collecting the input or the output.
    ///
    /// Write the input in chunks with ``write(_:to:)``, then call ``finish(to:)`` to emit the rest of the frame. The
    /// consumer receives chunks of at most 64 KiB, and the compression workspace depends on the compression level, not on
    /// the input length. These operations are synchronous and belong on a background executor.
    ///
    /// Any error closes the compressor. Discard its partial output and create a new compressor for a retry.
    public struct StreamCompressor: ~Copyable {
        private let context: OpaquePointer
        private let sourceByteCount: Int
        private let maximumCompressedByteCount: Int
        private var readByteCount = 0
        private var closed = false
        private var buffer = Data(count: Zstd.streamChunkByteCount)
        /// The number of compressed bytes delivered to the consumer.
        public private(set) var writtenByteCount = 0

        /// Creates a compressor for one frame.
        ///
        /// - Parameters:
        ///   - sourceByteCount: The exact number of input bytes, which the frame header declares.
        ///   - maximumCompressedByteCount: The most compressed bytes the frame may take. A larger frame fails with
        ///     ``StreamError/outputLimitExceeded`` before the exceeding chunk reaches the consumer.
        ///   - options: The compression options.
        public init(
            sourceByteCount: Int,
            maximumCompressedByteCount: Int,
            options: CompressionOptions = .init()
        ) throws(StreamError) {
            guard sourceByteCount >= 0, maximumCompressedByteCount >= 0 else {
                throw .invalidByteCount
            }
            guard let context = ZSTD_createCCtx() else {
                throw .notEnoughMemory
            }
            do {
                try Zstd.checkStream(ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, options.level.rawValue))
                try Zstd.checkStream(ZSTD_CCtx_setPledgedSrcSize(context, UInt64(sourceByteCount)))
            } catch {
                ZSTD_freeCCtx(context)
                throw error
            }
            self.context = context
            self.sourceByteCount = sourceByteCount
            self.maximumCompressedByteCount = maximumCompressedByteCount
        }

        /// Compresses one input chunk and delivers the compressed bytes that are ready.
        ///
        /// The consumer receives nothing for a chunk that exceeds the declared input byte count.
        ///
        /// - Throws: A ``StreamError``, or the error `consume` throws.
        public mutating func write(_ bytes: Data, to consume: (Data) throws -> Void) throws {
            guard !closed else {
                throw StreamError.closed
            }
            do {
                guard bytes.count <= sourceByteCount - readByteCount else {
                    throw StreamError.inputSizeMismatch
                }
                readByteCount += bytes.count
                try process(bytes, directive: ZSTD_e_continue, consume: consume)
            } catch {
                closed = true
                throw error
            }
        }

        /// Finishes the frame and delivers its remaining bytes.
        ///
        /// - Throws: ``StreamError/inputSizeMismatch`` unless exactly the declared number of input bytes was written,
        ///   another ``StreamError``, or the error `consume` throws.
        public mutating func finish(to consume: (Data) throws -> Void) throws {
            guard !closed else {
                throw StreamError.closed
            }
            closed = true
            guard readByteCount == sourceByteCount else {
                throw StreamError.inputSizeMismatch
            }
            try process(Data(), directive: ZSTD_e_end, consume: consume)
        }

        private mutating func process(_ bytes: Data, directive: ZSTD_EndDirective, consume: (Data) throws -> Void) throws {
            let context = context
            try bytes.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
                while true {
                    let (remaining, written) = buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        let remaining = ZSTD_compressStream2(context, &output, &input, directive)
                        return (remaining, output.pos)
                    }
                    try Zstd.checkStream(remaining)
                    guard written <= maximumCompressedByteCount - writtenByteCount else {
                        throw StreamError.outputLimitExceeded
                    }
                    if written > 0 {
                        writtenByteCount += written
                        try consume(buffer.prefix(written))
                    }
                    if directive == ZSTD_e_end ? remaining == 0 : input.pos == input.size {
                        return
                    }
                }
            }
        }

        deinit {
            ZSTD_freeCCtx(context)
        }
    }
}
