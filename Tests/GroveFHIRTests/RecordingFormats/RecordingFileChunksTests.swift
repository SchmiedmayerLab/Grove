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


@Suite
struct RecordingFileChunksTests {
    @Test
    func iteratorsKeepIndependentPositionsAndRetainTheSnapshot() async throws {
        let bytes = Data((0..<131_073).map { UInt8(truncatingIfNeeded: $0) })
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        var iterator = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count).chunks.makeAsyncIterator()
        try FileManager.default.removeItem(at: fixture.source)
        let first = try #require(try await iterator.next())
        #expect(first == bytes.prefix(65_536))
        var copy = iterator
        let second = try #require(try await iterator.next())
        #expect(second == bytes[65_536..<131_072])
        let remainder = [try await iterator.next(), try await iterator.next(), try await iterator.next()]
        #expect(remainder == [bytes.suffix(1), nil, nil])
        let copiedRemainder = [try await copy.next(), try await copy.next(), try await copy.next()]
        #expect(copiedRemainder == [second, bytes.suffix(1), nil])
        // Keeping the first chunk must not expose a buffer overwritten by later reads.
        #expect(first == bytes.prefix(65_536))
    }

    @Test
    func sequenceDeliversTheExactBytes() async throws {
        let bytes = Data(repeating: 0xA5, count: 200_001)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        var received = Data()
        for try await chunk in file.chunks {
            #expect(!chunk.isEmpty && chunk.count <= 64 * 1024)
            received.append(chunk)
        }
        #expect(received == bytes)
    }

    @Test
    func cancellationLeavesThePositionAvailableToAnotherTask() async throws {
        let fixture = try RecordingFileFixture(Data(repeating: 0xA5, count: 65_537))
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: 65_537)
        let cancelled = Task { () async throws -> RecordingFile.Chunks.AsyncIterator in
            var iterator = file.chunks.makeAsyncIterator()
            let first = try await iterator.next()
            #expect(first?.count == 65_536)
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { _ = try await iterator.next() }
            return iterator
        }
        var resumed = try await cancelled.value
        let remainder = [try await resumed.next(), try await resumed.next()]
        #expect(remainder == [Data([0xA5]), nil])
    }
}
