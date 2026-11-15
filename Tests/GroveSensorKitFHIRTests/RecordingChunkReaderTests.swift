//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


struct RecordingChunkReaderTests {
    @Test
    func readersKeepIndependentPositionsAndRetainTheSnapshot() throws {
        let bytes = Data((0..<131_073).map { UInt8(truncatingIfNeeded: $0) })
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        var reader = try RecordingFile.stage(copying: fixture.source, maximumByteCount: Int64(bytes.count)).makeChunkReader()
        try FileManager.default.removeItem(at: fixture.source)
        let firstChunk = try reader.readNextChunk()
        let first = try #require(firstChunk)
        #expect(first == bytes.prefix(65_536))
        var copy = reader
        let secondChunk = try reader.readNextChunk()
        let second = try #require(secondChunk)
        #expect(second == bytes[65_536..<131_072])
        let remainder = try [reader.readNextChunk(), reader.readNextChunk(), reader.readNextChunk()]
        #expect(remainder == [bytes.suffix(1), nil, nil])
        let copiedRemainder = try [copy.readNextChunk(), copy.readNextChunk(), copy.readNextChunk()]
        #expect(copiedRemainder == [second, bytes.suffix(1), nil])
        // Keeping the first chunk must not expose a buffer overwritten by later reads.
        #expect(first == bytes.prefix(65_536))
    }

    @Test
    func cancellationLeavesThePositionAvailableToAnotherTask() async throws {
        let fixture = try RecordingFileFixture(Data(repeating: 0xA5, count: 65_537))
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: 65_537)
        let cancelled = Task { () async throws -> RecordingFile.ChunkReader in
            var reader = file.makeChunkReader()
            let first = try reader.readNextChunk()
            #expect(first?.count == 65_536)
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try reader.readNextChunk() }
            return reader
        }
        var resumed = try await cancelled.value
        let remainder = try [resumed.readNextChunk(), resumed.readNextChunk()]
        #expect(remainder == [Data([0xA5]), nil])
        var independent = file.makeChunkReader()
        let first = try independent.readNextChunk()
        #expect(first?.count == 65_536)
    }
}
