//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import libzstd
import Testing


struct ZstdStreamDecompressionTests {
    private enum ConsumerError: Error { case stopped }

    private static func frameWithoutContentSize(_ input: Data) throws -> Data {
        let context = try #require(ZSTD_createCCtx())
        defer { ZSTD_freeCCtx(context) }
        try #require(ZSTD_isError(ZSTD_CCtx_setParameter(context, ZSTD_c_contentSizeFlag, 0)) == 0)
        try #require(ZSTD_isError(ZSTD_CCtx_setParameter(context, ZSTD_c_checksumFlag, 1)) == 0)
        var output = Data(count: ZSTD_compressBound(input.count))
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                ZSTD_compress2(context, destination.baseAddress, destination.count, source.baseAddress, source.count)
            }
        }
        try #require(ZSTD_isError(written) == 0)
        return output.prefix(written)
    }

    private static func decompress(_ input: Data, expectedCount: Int, chunkSize: Int, windowBytes: Int = 8 * 1024 * 1024) throws -> Data {
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(input.count), decodedByteCount: Int64(expectedCount), maximumWindowByteCount: windowBytes
        )
        var result = Data()
        for offset in stride(from: 0, to: input.count, by: chunkSize) {
            try decoder.write(input.subdata(in: offset..<min(input.count, offset + chunkSize))) { chunk in
                #expect(chunk.count <= 64 * 1024)
                result.append(chunk)
            }
        }
        try decoder.finish()
        #expect(decoder.decodedByteCount == result.count)
        return result
    }

    @Test
    func oneShotAndStreamedFramesDecodeWithArbitraryBoundaries() throws {
        for input in [Data(), Data(String(repeating: "timestamp,device,value\n1,Watch,72\n", count: 40_000).utf8)] {
            let compressed = try Zstd.compress(input)
            var compressor = try Zstd.StreamCompressor(sourceByteCount: Int64(input.count), maximumOutputByteCount: 2 * 1024 * 1024)
            var streamed = Data()
            try compressor.write(input) { streamed.append($0) }
            try compressor.finish { streamed.append($0) }
            for frame in [compressed, streamed] {
                for chunkSize in [1, 7, 1023, 65_537] {
                    #expect(try Self.decompress(frame, expectedCount: input.count, chunkSize: chunkSize) == input)
                }
            }
        }
    }

    @Test
    func framesWithoutContentSizeUseTheAdmittedLengthAndVerifyTheirChecksum() throws {
        let source = Data(String(repeating: "recording\n", count: 1000).utf8)
        let frame = try Self.frameWithoutContentSize(source)
        #expect(frame.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, $0.count) } == ZSTD_CONTENTSIZE_UNKNOWN)
        #expect(try Self.decompress(frame, expectedCount: source.count, chunkSize: 1) == source)
        var damaged = frame
        damaged[damaged.count - 1] ^= 1
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(damaged.count), decodedByteCount: Int64(source.count), maximumWindowByteCount: 8 * 1024 * 1024
        )
        #expect(throws: (any Error).self) { try decoder.write(damaged) { _ in } }
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func truncatedFramesCannotBeFinalized() throws {
        let frame = try Zstd.compress(Data("synthetic recording".utf8))
        for count in 1..<frame.count {
            #expect(throws: (any Error).self) {
                try Self.decompress(Data(frame.prefix(count)), expectedCount: 19, chunkSize: 1)
            }
        }
    }

    @Test
    func additionalFramesAndTrailingBytesAreRejectedWithinOrAcrossChunks() throws {
        let source = Data("recording".utf8)
        let frame = try Zstd.compress(source)
        for suffix in [frame, Data([0])] {
            let input = frame + suffix
            for chunkSize in [1, frame.count, input.count] {
                #expect(throws: Zstd.StreamDecompressor.StreamError.trailingData) {
                    try Self.decompress(input, expectedCount: source.count, chunkSize: chunkSize)
                }
            }
        }
    }

    @Test
    func skippableAndInvalidFramesAreRejected() throws {
        // An empty skippable Zstandard frame, followed by an invalid frame header.
        for bytes in [Data([0x50, 0x2a, 0x4d, 0x18, 0, 0, 0, 0]), Data("not a zstd frame".utf8)] {
            for chunkSize in [1, bytes.count] {
                #expect(throws: (any Error).self) { try Self.decompress(bytes, expectedCount: 0, chunkSize: chunkSize) }
            }
        }
    }

    @Test
    func decodedLengthAndHistoryWindowAreIndependentLimits() throws {
        let source = Data(repeating: 0x71, count: 1_048_577)
        let frame = try Zstd.compress(source)
        #expect(try Self.decompress(frame, expectedCount: source.count, chunkSize: 127) == source)
        for count in [source.count - 1, source.count + 1] {
            #expect(throws: Zstd.StreamDecompressor.StreamError.outputSizeMismatch) {
                try Self.decompress(frame, expectedCount: count, chunkSize: 127)
            }
        }
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(frame.count), decodedByteCount: Int64(source.count), maximumWindowByteCount: 1024
        )
        var delivered = false
        #expect(throws: (any Error).self) { try decoder.write(frame) { _ in delivered = true } }
        #expect(!delivered)
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func excessInputAndOutputAreNotDelivered() throws {
        let frame = try Zstd.compress(Data("recording".utf8))
        var shortInput = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(frame.count - 1), decodedByteCount: 9, maximumWindowByteCount: 1024
        )
        var shortOutput = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(frame.count), decodedByteCount: 0, maximumWindowByteCount: 1024
        )
        var delivered = false
        #expect(throws: Zstd.StreamDecompressor.StreamError.inputSizeMismatch) { try shortInput.write(frame) { _ in delivered = true } }
        #expect(throws: Zstd.StreamDecompressor.StreamError.outputSizeMismatch) { try shortOutput.write(frame) { _ in delivered = true } }
        #expect(!delivered)
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try shortInput.finish() }
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try shortOutput.finish() }
    }

    @Test
    func incompleteDeclaredInputAndCompletedDecodersCannotBeReused() throws {
        let frame = try Zstd.compress(Data())
        var incomplete = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(frame.count + 1), decodedByteCount: 0, maximumWindowByteCount: 1024
        )
        try incomplete.write(frame) { _ in }
        #expect(throws: Zstd.StreamDecompressor.StreamError.inputSizeMismatch) { try incomplete.finish() }
        var complete = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(frame.count), decodedByteCount: 0, maximumWindowByteCount: 1024
        )
        try complete.write(frame) { _ in }
        try complete.finish()
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try complete.finish() }
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try complete.write(Data()) { _ in } }
    }

    @Test
    func consumerFailureClosesTheDecoder() throws {
        let frame = try Zstd.compress(Data("recording".utf8))
        var decoder = try Zstd.StreamDecompressor(compressedByteCount: Int64(frame.count), decodedByteCount: 9, maximumWindowByteCount: 1024)
        #expect(throws: ConsumerError.stopped) { try decoder.write(frame) { _ in throw ConsumerError.stopped } }
        #expect(throws: Zstd.StreamDecompressor.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func cancellationAfterOutputCannotReportSuccess() async throws {
        let frame = try Zstd.compress(Data("recording".utf8))
        let task = Task {
            var decoder = try Zstd.StreamDecompressor(compressedByteCount: Int64(frame.count), decodedByteCount: 9, maximumWindowByteCount: 1024)
            try decoder.write(frame) { _ in withUnsafeCurrentTask { $0?.cancel() } }
            try decoder.finish()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func invalidConfigurationIsRejectedBeforeReading() {
        for (compressed, decoded) in [(Int64(0), Int64(0)), (-1, 0), (1, -1)] {
            #expect(throws: Zstd.StreamDecompressor.StreamError.invalidByteCount) {
                _ = try Zstd.StreamDecompressor(compressedByteCount: compressed, decodedByteCount: decoded, maximumWindowByteCount: 1024)
            }
        }
        for window in [0, -1, 1023, Int.max] {
            #expect(throws: Zstd.StreamDecompressor.StreamError.invalidWindowLimit) {
                _ = try Zstd.StreamDecompressor(compressedByteCount: 1, decodedByteCount: 0, maximumWindowByteCount: window)
            }
        }
    }
}
