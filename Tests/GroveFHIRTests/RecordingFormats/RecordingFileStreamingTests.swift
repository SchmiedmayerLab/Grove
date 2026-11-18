//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


@Suite
struct RecordingFileStreamingTests {
    private enum Failure: Error {
        case source
    }

    @Test
    func streamingAndDecompressionPreserveOriginalBytes() async throws {
        let bytes = Data(repeating: 0x5A, count: 131_073)
        let file = try await RecordingFile.stage(chunks: Self.stream([Data(), bytes.prefix(7), bytes.dropFirst(7)]), maximumByteCount: 131_073)
        #expect(file.byteCount == bytes.count && file.attachmentSHA1 == bytes.attachmentSHA1)
        let compressed = try #require(try file.zstandardCompressed())
        let decoded = try compressed.zstandardDecompressed(decompressedByteCount: bytes.count, maximumWindowByteCount: 1024 * 1024)
        var actual = Data()
        try decoded.readChunks { actual.append($0) }
        #expect(actual == bytes && decoded.attachmentSHA1 == bytes.attachmentSHA1)
        for count in [bytes.count - 1, bytes.count + 1] {
            #expect(throws: (any Error).self) { try compressed.zstandardDecompressed(decompressedByteCount: count) }
        }
    }

    @Test
    func invalidStreamsNeverReturnPartialFiles() async throws {
        await #expect(throws: RecordingFile.FileError.invalidByteLimit) {
            try await RecordingFile.stage(chunks: Self.stream([Data([1])]), maximumByteCount: 0)
        }
        await #expect(throws: RecordingFile.FileError.emptySource) {
            try await RecordingFile.stage(chunks: Self.stream([Data()]), maximumByteCount: 1)
        }
        await #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try await RecordingFile.stage(chunks: Self.stream([Data([1]), Data([2])]), maximumByteCount: 1)
        }
        let failed = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.yield(Data([1]))
            continuation.finish(throwing: Failure.source)
        }
        await #expect(throws: Failure.source) { try await RecordingFile.stage(chunks: failed, maximumByteCount: 2) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RecordingFile.stage(chunks: Self.stream([Data([1])]), maximumByteCount: 1)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test
    func damagedFramesAndCancellationNeverReturnADecodedSnapshot() async throws {
        let bytes = Data(repeating: 3, count: 131_073)
        let original = try await RecordingFile.stage(chunks: Self.stream([bytes]), maximumByteCount: bytes.count)
        let compressed = try #require(try original.zstandardCompressed())
        var frame = Data()
        try compressed.readChunks { frame.append($0) }
        for damaged in [frame.dropLast(), frame + Data([0]), frame + frame] {
            let file = try await RecordingFile.stage(chunks: Self.stream([damaged]), maximumByteCount: 8192)
            #expect(throws: (any Error).self) { try file.zstandardDecompressed(decompressedByteCount: bytes.count) }
        }
        #expect(throws: RecordingFile.FileError.invalidByteLimit) { try compressed.zstandardDecompressed(decompressedByteCount: 0) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try compressed.zstandardDecompressed(decompressedByteCount: bytes.count)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }
}


extension RecordingFileStreamingTests {
    fileprivate static func stream(_ chunks: [Data]) -> AsyncStream<Data> {
        AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
