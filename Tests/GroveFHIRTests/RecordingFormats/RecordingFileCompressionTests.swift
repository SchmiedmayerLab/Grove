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


@Suite
struct RecordingFileCompressionTests {
    @Test
    func compressedSnapshotPreservesTheExactSource() throws {
        let bytes = Data(repeating: 0x5A, count: 131_073)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        let compressed = try #require(try file.zstandardCompressed())
        #expect(compressed.byteCount < file.byteCount)
        var decoded = Data()
        var decoder = try Zstd.StreamDecompressor(
            compressedByteCount: compressed.byteCount,
            decompressedByteCount: file.byteCount,
            maximumWindowByteCount: 8 * 1024 * 1024
        )
        try compressed.readChunks { chunk in try decoder.write(chunk) { decoded.append($0) } }
        try decoder.finish()
        #expect(decoded == bytes)
        var original = Data()
        try file.readChunks { original.append($0) }
        #expect(original == bytes)
        let again = try #require(try file.zstandardCompressed())
        var first = Data()
        var second = Data()
        try compressed.readChunks { first.append($0) }
        try again.readChunks { second.append($0) }
        #expect(first == second)
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
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: count)
        #expect(try file.zstandardCompressed() == nil)
    }

    @Test
    func cancellationCannotReturnAFallback() async throws {
        let fixture = try RecordingFileFixture(Data(repeating: 1, count: 4096))
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: 4096)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try file.zstandardCompressed()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try file.zstandardCompressed() != nil)
    }
}
