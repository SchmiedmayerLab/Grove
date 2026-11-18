//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import Testing


@Suite
struct ZstdStreamDecompressorTests {
    private enum ConsumerError: Error {
        case stopped
    }

    private static let source = Data(String(repeating: "recording\n", count: 10).utf8)

    /// A frame that doesn't state its content size: a frame header with a content checksum and a 1 KiB window, one raw
    /// block holding ``source``, and the low 32 bits of the XXH64 digest of ``source``.
    private static let frameWithoutContentSize = Data([0x28, 0xB5, 0x2F, 0xFD, 0x04, 0x00, 0x21, 0x03, 0x00])
        + source
        + Data([0xEA, 0x25, 0xF2, 0x3A])

    private static func decompress(
        _ input: Data,
        expectedCount: Int,
        chunkSize: Int,
        windowBytes: Int = 8 * 1024 * 1024
    ) throws -> Data {
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: input.count,
            decompressedByteCount: expectedCount,
            maximumWindowByteCount: windowBytes
        )
        var result = Data()
        for offset in stride(from: 0, to: input.count, by: chunkSize) {
            try decoder.write(input.subdata(in: offset..<min(input.count, offset + chunkSize))) { chunk in
                #expect(chunk.count <= 64 * 1024)
                result.append(chunk)
            }
        }
        try decoder.finish()
        #expect(decoder.writtenByteCount == result.count)
        return result
    }

    @Test
    func oneShotAndStreamedFramesDecodeWithArbitraryBoundaries() throws {
        for input in [Data(), Data(String(repeating: "timestamp,device,value\n1,Watch,72\n", count: 40_000).utf8)] {
            let compressed = try Zstd.compress(input)
            var compressor = try Zstd.StreamCompressor(sourceByteCount: input.count, maximumCompressedByteCount: 2 * 1024 * 1024)
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
    func framesWithoutContentSizeUseTheDeclaredLengthAndVerifyTheirChecksum() throws {
        let frame = Self.frameWithoutContentSize
        #expect(throws: Zstd.CompressionError.self) { try Zstd.decompress(frame) }
        #expect(try Self.decompress(frame, expectedCount: Self.source.count, chunkSize: 1) == Self.source)
        var damaged = frame
        damaged[damaged.count - 1] ^= 1
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: damaged.count,
            decompressedByteCount: Self.source.count,
            maximumWindowByteCount: 8 * 1024 * 1024
        )
        let checksumError = #expect(throws: Zstd.StreamError.self) { try decoder.write(damaged) { _ in } }
        guard case .codec = checksumError else {
            Issue.record("A damaged checksum must fail in the codec, not \(String(describing: checksumError))")
            return
        }
        #expect(throws: Zstd.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func truncatedFramesCannotBeFinalized() throws {
        let frame = try Zstd.compress(Data("synthetic recording".utf8))
        for count in 1..<frame.count {
            #expect(throws: Zstd.StreamError.truncatedFrame) {
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
                #expect(throws: Zstd.StreamError.trailingData) {
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
                #expect(throws: Zstd.StreamError.invalidFrame) { try Self.decompress(bytes, expectedCount: 0, chunkSize: chunkSize) }
            }
        }
    }

    @Test(arguments: 1...3)
    func magicNumberDivergingAfterAMatchingPrefixIsAnInvalidFrame(chunkSize: Int) throws {
        // A prefix of the little-endian Zstandard magic number 0xFD2FB528, then a diverging third or fourth byte.
        for diverging in [Data([0x28, 0xb5, 0x00, 0xfd, 0, 0, 0, 0]), Data([0x28, 0xb5, 0x2f, 0x00, 0, 0, 0, 0])] {
            #expect(throws: Zstd.StreamError.invalidFrame) { try Self.decompress(diverging, expectedCount: 0, chunkSize: chunkSize) }
        }
    }

    @Test
    func decompressedLengthAndHistoryWindowAreIndependentLimits() throws {
        let source = Data(repeating: 0x71, count: 1_048_577)
        let frame = try Zstd.compress(source)
        #expect(try Self.decompress(frame, expectedCount: source.count, chunkSize: 127) == source)
        for count in [source.count - 1, source.count + 1] {
            #expect(throws: Zstd.StreamError.outputSizeMismatch) {
                try Self.decompress(frame, expectedCount: count, chunkSize: 127)
            }
        }
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count,
            decompressedByteCount: source.count,
            maximumWindowByteCount: 1024
        )
        var delivered = false
        let windowError = #expect(throws: Zstd.StreamError.self) { try decoder.write(frame) { _ in delivered = true } }
        guard case .codec = windowError else {
            Issue.record("A frame that needs a larger window must fail in the codec, not \(String(describing: windowError))")
            return
        }
        #expect(!delivered)
        #expect(throws: Zstd.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func excessInputAndOutputAreNotDelivered() throws {
        let frame = try Zstd.compress(Data("recording".utf8))
        var shortInput = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count - 1,
            decompressedByteCount: 9,
            maximumWindowByteCount: 1024
        )
        var shortOutput = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count,
            decompressedByteCount: 0,
            maximumWindowByteCount: 1024
        )
        var delivered = false
        #expect(throws: Zstd.StreamError.inputSizeMismatch) { try shortInput.write(frame) { _ in delivered = true } }
        #expect(throws: Zstd.StreamError.outputSizeMismatch) { try shortOutput.write(frame) { _ in delivered = true } }
        #expect(!delivered)
        #expect(throws: Zstd.StreamError.closed) { try shortInput.finish() }
        #expect(throws: Zstd.StreamError.closed) { try shortOutput.finish() }
    }

    @Test
    func incompleteDeclaredInputAndCompletedDecodersCannotBeReused() throws {
        let frame = try Zstd.compress(Data())
        var incomplete = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count + 1,
            decompressedByteCount: 0,
            maximumWindowByteCount: 1024
        )
        try incomplete.write(frame) { _ in }
        #expect(throws: Zstd.StreamError.inputSizeMismatch) { try incomplete.finish() }
        var complete = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count,
            decompressedByteCount: 0,
            maximumWindowByteCount: 1024
        )
        try complete.write(frame) { _ in }
        try complete.finish()
        #expect(throws: Zstd.StreamError.closed) { try complete.finish() }
        #expect(throws: Zstd.StreamError.closed) { try complete.write(Data()) { _ in } }
    }

    @Test
    func consumerFailureClosesTheDecoder() throws {
        let frame = try Zstd.compress(Data("recording".utf8))
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: frame.count,
            decompressedByteCount: 9,
            maximumWindowByteCount: 1024
        )
        #expect(throws: ConsumerError.stopped) { try decoder.write(frame) { _ in throw ConsumerError.stopped } }
        #expect(throws: Zstd.StreamError.closed) { try decoder.finish() }
    }

    @Test
    func invalidConfigurationIsRejectedBeforeReading() {
        for (compressed, decompressed) in [(0, 0), (-1, 0), (1, -1)] {
            #expect(throws: Zstd.StreamError.invalidByteCount) {
                _ = try Zstd.StreamDecompressor(
                    compressedByteCount: compressed,
                    decompressedByteCount: decompressed,
                    maximumWindowByteCount: 1024
                )
            }
        }
        for window in [0, -1, 1023, Int.max] {
            #expect(throws: Zstd.StreamError.invalidWindowLimit) {
                _ = try Zstd.StreamDecompressor(compressedByteCount: 1, decompressedByteCount: 0, maximumWindowByteCount: window)
            }
        }
    }
}
