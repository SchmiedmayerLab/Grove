//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveFoundation
import Testing


struct RecordingFileCompressionTests {
    @Test
    func compressedSnapshotPreservesTheExactSourceAndFitsTheStoredBudget() throws {
        let bytes = Data(repeating: 0x5A, count: 131_073)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: Int64(bytes.count))
        let compressed = try #require(try file.zstandardCompressedIfSmaller(maximumByteCount: 4096, maximumWindowByteCount: 1024))
        #expect(compressed.byteCount < file.byteCount)
        var decoded = Data()
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: Int64(compressed.byteCount), decodedByteCount: Int64(file.byteCount), maximumWindowByteCount: 1024
        )
        try compressed.readChunks { chunk in try decoder.write(chunk) { decoded.append($0) } }
        try decoder.finish()
        #expect(decoded == bytes)
        var original = Data()
        try file.readChunks { original.append($0) }
        #expect(original == bytes)
        let again = try #require(try file.zstandardCompressedIfSmaller(maximumByteCount: 4096, maximumWindowByteCount: 1024))
        var first = Data(), second = Data()
        try compressed.readChunks { first.append($0) }
        try again.readChunks { second.append($0) }
        #expect(first == second)
        #expect(try file.zstandardCompressedIfSmaller(maximumByteCount: compressed.byteCount, maximumWindowByteCount: 1024) != nil)
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try file.zstandardCompressedIfSmaller(maximumByteCount: compressed.byteCount - 1, maximumWindowByteCount: 1024)
        }
    }

    @Test(arguments: [1, 65_537])
    func nonBeneficialCompressionKeepsTheOriginal(count: Int) throws {
        var state: UInt32 = 0xA371_9F25
        let bytes = Data((0..<count).map { _ in
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return UInt8(truncatingIfNeeded: state)
        })
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: Int64(count))
        #expect(try file.zstandardCompressedIfSmaller(maximumByteCount: count) == nil)
        if count > 1 {
            #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
                try file.zstandardCompressedIfSmaller(maximumByteCount: count - 1)
            }
        }
    }

    @Test
    func invalidBudgetsAndCancellationCannotReturnAFallback() async throws {
        let fixture = try RecordingFileFixture(Data(repeating: 1, count: 4096))
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: 4096)
        #expect(throws: RecordingFile.FileError.invalidByteLimit) { try file.zstandardCompressedIfSmaller(maximumByteCount: 0) }
        for window in [0, 512, Int.max] {
            #expect(throws: Zstd.StreamCompressor.StreamError.invalidWindowLimit) {
                try file.zstandardCompressedIfSmaller(maximumByteCount: 4096, maximumWindowByteCount: window)
            }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try file.zstandardCompressedIfSmaller(maximumByteCount: 4096)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try file.zstandardCompressedIfSmaller(maximumByteCount: 4096) != nil)
    }
}
