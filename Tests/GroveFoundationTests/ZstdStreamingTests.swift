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


struct ZstdStreamingTests {
    private enum ConsumerError: Error { case stopped }

    private static func compress(_ input: Data, chunkSize: Int, limit: Int64 = 4 * 1024 * 1024) throws -> Data {
        var compressor = try Zstd.StreamCompressor(sourceByteCount: Int64(input.count), maximumOutputByteCount: limit)
        var output = Data()
        func consume(_ chunk: Data) {
            #expect(chunk.count <= 64 * 1024)
            output.append(chunk)
        }
        for offset in stride(from: 0, to: input.count, by: chunkSize) {
            try compressor.write(input.subdata(in: offset..<min(input.count, offset + chunkSize)), to: consume)
        }
        try compressor.finish(to: consume)
        #expect(compressor.compressedByteCount == output.count)
        return output
    }

    @Test
    func emptyAndBytewiseInputRoundTrip() throws {
        for input in [Data(), Data("timestamp,value,device\n1,72,Watch\n".utf8)] {
            let compressed = try Self.compress(input, chunkSize: 1)
            #expect(try Zstd.decompress(compressed, maximumDecompressedSize: input.count) == input)
        }
    }

    @Test
    func arbitraryChunkingPreservesOneFrameAndExactBytes() throws {
        var state: UInt64 = 0x12345678
        let input = Data((0..<1_048_577).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return UInt8(truncatingIfNeeded: state)
        })
        let reference = try Self.compress(input, chunkSize: 64 * 1024)
        for size in [31, 4093, 130_001] {
            let compressed = try Self.compress(input, chunkSize: size)
            #expect(compressed == reference)
            #expect(try Zstd.decompress(compressed, maximumDecompressedSize: input.count) == input)
        }
    }

    @Test
    func compressedLimitIsInclusiveAndRejectedOutputIsNotDelivered() throws {
        let input = Data(String(repeating: "1787009400,72,3,Watch\n", count: 1000).utf8)
        let expected = try Self.compress(input, chunkSize: 127)
        #expect(expected.count < input.count / 10)
        #expect(try Self.compress(input, chunkSize: 127, limit: Int64(expected.count)) == expected)
        #expect(throws: Zstd.StreamCompressor.StreamError.outputLimitExceeded) {
            try Self.compress(input, chunkSize: 127, limit: Int64(expected.count - 1))
        }
        var compressor = try Zstd.StreamCompressor(sourceByteCount: 0, maximumOutputByteCount: 0)
        var delivered = false
        #expect(throws: Zstd.StreamCompressor.StreamError.outputLimitExceeded) {
            try compressor.finish { _ in delivered = true }
        }
        #expect(!delivered)
    }

    @Test
    func wrongSourceSizeAndCompletedStreamsCannotBeReused() throws {
        var short = try Zstd.StreamCompressor(sourceByteCount: 3, maximumOutputByteCount: 1024)
        try short.write(Data("ab".utf8)) { _ in }
        #expect(throws: Zstd.StreamCompressor.StreamError.inputSizeMismatch) { try short.finish { _ in } }
        #expect(throws: Zstd.StreamCompressor.StreamError.closed) { try short.write(Data("c".utf8)) { _ in } }
        var long = try Zstd.StreamCompressor(sourceByteCount: 1, maximumOutputByteCount: 1024)
        #expect(throws: Zstd.StreamCompressor.StreamError.inputSizeMismatch) { try long.write(Data("ab".utf8)) { _ in } }
        #expect(throws: Zstd.StreamCompressor.StreamError.closed) { try long.finish { _ in } }
        var empty = try Zstd.StreamCompressor(sourceByteCount: 0, maximumOutputByteCount: 1024)
        try empty.finish { _ in }
        #expect(throws: Zstd.StreamCompressor.StreamError.closed) { try empty.finish { _ in } }
    }

    @Test
    func consumerFailureClosesTheStream() throws {
        var compressor = try Zstd.StreamCompressor(sourceByteCount: 0, maximumOutputByteCount: 1024)
        #expect(throws: ConsumerError.stopped) { try compressor.finish { _ in throw ConsumerError.stopped } }
        #expect(throws: Zstd.StreamCompressor.StreamError.closed) { try compressor.write(Data()) { _ in } }
    }

    @Test
    func cancellationAfterLastOutputIsNotSuccess() async throws {
        let task = Task {
            var compressor = try Zstd.StreamCompressor(sourceByteCount: 0, maximumOutputByteCount: 1024)
            try compressor.finish { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
