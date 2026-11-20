//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
@testable import GroveFHIRContract
import Testing


@Suite
struct RecordingFileTests {
    private enum ConsumerError: Error {
        case stopped
    }

    @Test
    func snapshotSurvivesSourceReplacementAndRemoval() throws {
        let bytes = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        #expect(file.byteCount == bytes.count && file.attachmentSHA1 == bytes.attachmentSHA1)
        try Data("replaced source".utf8).write(to: fixture.source, options: .atomic)
        try FileManager.default.removeItem(at: fixture.source)
        #expect(try contents(file) == bytes)
        var attributes = stat()
        #expect(fstat(file.storage.descriptor, &attributes) == 0)
        #expect(attributes.st_nlink == 0 && attributes.st_mode & 0o777 == 0o600)
    }

    @Test
    func independentConcurrentReadersAndSharedLifetime() async throws {
        let bytes = Data(repeating: 0xA5, count: 300_001)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        var original: RecordingFile? = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        weak var storage = original?.storage
        var copy = original
        original = nil
        #expect(storage != nil)
        try await withThrowingTaskGroup(of: Data.self) { group in
            let file = try #require(copy)
            for _ in 0..<8 {
                group.addTask { try contents(file) }
            }
            for try await read in group { #expect(read == bytes) }
        }
        #expect(storage != nil)
        copy = nil
        #expect(storage == nil)
        #expect(try Data(contentsOf: fixture.source) == bytes)
    }

    @Test
    func concurrentStagingKeepsEverySnapshotUsable() async throws {
        let bytes = Data(repeating: 0xA5, count: 257)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    for _ in 0..<32 {
                        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
                        #expect(try contents(file) == bytes)
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(try Data(contentsOf: fixture.source) == bytes)
    }

    @Test
    func failedOrCancelledReaderDoesNotInvalidateTheSnapshot() async throws {
        let fixture = try RecordingFileFixture(Data(repeating: 0xA5, count: 100_001))
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: 100_001)
        #expect(throws: ConsumerError.stopped) { try file.readChunks { _ in throw ConsumerError.stopped } }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try file.readChunks { _ in Issue.record("Cancelled read delivered bytes") } }
        }
        await cancelled.value
        let cancelledAtEnd = Task {
            var delivered = 0
            #expect(throws: CancellationError.self) {
                try file.readChunks { chunk in
                    delivered += chunk.count
                    if delivered == file.byteCount { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            #expect(delivered == file.byteCount)
        }
        await cancelledAtEnd.value
        #expect(try contents(file).count == 100_001)
    }

    @Test
    func invalidSourcesFailWithoutChangingTheCallerFile() throws {
        let fixture = try RecordingFileFixture(Data("caller bytes".utf8))
        defer { withExtendedLifetime(fixture) {} }
        let missing = fixture.directory.appendingPathComponent("missing")
        let symlink = fixture.directory.appendingPathComponent("symlink")
        let invalidPath = URL(fileURLWithPath: fixture.source.path + "\u{0}suffix")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture.source)
        for source in [missing, symlink, invalidPath] {
            #expect(throws: RecordingFile.FileError.sourceUnavailable) { try RecordingFile.stage(copying: source, maximumByteCount: 100) }
        }
        #expect(throws: RecordingFile.FileError.sourceNotRegular) {
            try RecordingFile.stage(copying: fixture.directory, maximumByteCount: 100)
        }
        let pipe = fixture.directory.appendingPathComponent("pipe")
        try #require(mkfifo(pipe.path, 0o600) == 0)
        #expect(throws: RecordingFile.FileError.sourceNotRegular) { try RecordingFile.stage(copying: pipe, maximumByteCount: 100) }
        try #require(chmod(fixture.source.path, 0) == 0)
        #expect(throws: RecordingFile.FileError.sourceUnavailable) { try RecordingFile.stage(copying: fixture.source, maximumByteCount: 100) }
        try #require(chmod(fixture.source.path, 0o600) == 0)
        #expect(try Data(contentsOf: fixture.source) == Data("caller bytes".utf8))
    }

    @Test
    func emptyAndOverLimitSourcesAreRefusedAndTheExactLimitSucceeds() throws {
        let empty = try RecordingFileFixture(Data())
        defer { withExtendedLifetime(empty) {} }
        #expect(throws: RecordingFile.FileError.emptySource) { try RecordingFile.stage(copying: empty.source, maximumByteCount: 1) }
        let fixture = try RecordingFileFixture(Data(repeating: 0xA5, count: 65_537))
        defer { withExtendedLifetime(fixture) {} }
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try RecordingFile.stage(copying: fixture.source, maximumByteCount: 65_536)
        }
        #expect(try RecordingFile.stage(copying: fixture.source, maximumByteCount: 65_537).byteCount == 65_537)
        for limit in [0, -1, Int(Int32.max) + 1] {
            #expect(throws: RecordingFile.FileError.invalidByteLimit) { try RecordingFile.stage(copying: fixture.source, maximumByteCount: limit) }
        }
        #expect(try Data(contentsOf: fixture.source).count == 65_537)
    }

    @Test
    func truncationAndGrowthAfterTheInitialSizeCheckAreDetected() throws {
        for length in [1, 200_001] {
            let fixture = try RecordingFileFixture(Data(repeating: 0xA5, count: 100_001))
            defer { withExtendedLifetime(fixture) {} }
            let source = open(fixture.source.path, O_RDONLY | O_CLOEXEC)
            try #require(source >= 0)
            defer { close(source) }
            var initial = stat()
            try #require(fstat(source, &initial) == 0)
            let writer = try FileHandle(forWritingTo: fixture.source)
            try writer.truncate(atOffset: UInt64(length))
            try writer.close()
            let expected: RecordingFile.FileError = length == 1 ? .sourceChanged : .byteLimitExceeded
            #expect(throws: expected) {
                try RecordingFile.copy(from: source, expected: initial, maximumByteCount: 100_001)
            }
        }
    }

    private func contents(_ file: RecordingFile) throws -> Data {
        var bytes = Data()
        try file.readChunks { chunk in
            #expect(!chunk.isEmpty && chunk.count <= 64 * 1024)
            bytes.append(chunk)
        }
        return bytes
    }
}
