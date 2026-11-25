//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
@testable import GroveHealthKit
import Testing


/// The writer behind `HKObject.copyAttachments(from:into:)`. HealthKit's own stream needs a store with attachments, which a
/// headless test has none of, so these tests feed the writer the chunks HealthKit would.
@Suite
struct AttachmentFileWriterTests {
    private struct StreamFailure: Error {}

    private static func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("attachment", isDirectory: false)
    }

    @Test("Chunks land in the file in order, with their count and both digests")
    func chunksAreWrittenAndDigested() throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let chunks = [Data("%PDF-1.7\n".utf8), Data(), Data(repeating: 0xAB, count: 70_000), Data("%%EOF\n".utf8)]
        let whole = chunks.reduce(into: Data()) { $0.append($1) }

        let writer = try AttachmentFileWriter(url: url)
        for chunk in chunks {
            try writer.append(chunk)
        }
        let written = try writer.finish()

        #expect(try Data(contentsOf: url) == whole)
        #expect(written.byteCount == whole.count)
        #expect(written.sha1 == Data(Insecure.SHA1.hash(data: whole)))
        #expect(written.sha256 == Data(SHA256.hash(data: whole)))
    }

    @Test("An attachment without bytes is an empty file with the digests of no bytes")
    func emptyAttachment() throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let written = try AttachmentFileWriter(url: url).finish()
        #expect(try Data(contentsOf: url).isEmpty)
        #expect(written.byteCount == 0)
        #expect(written.sha1 == Data(Insecure.SHA1.hash(data: Data())))
        #expect(written.sha256 == Data(SHA256.hash(data: Data())))
    }

    @Test("Streamed chunks land in the file; the last one ends the copy")
    func streamedCopy() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let written = try await AttachmentFileWriter.copy(to: url) { handler in
            handler(Data("%PDF".utf8), nil, false)
            handler(Data("-1.7".utf8), nil, true)
            return Progress(totalUnitCount: 1)
        }
        #expect(try Data(contentsOf: url) == Data("%PDF-1.7".utf8))
        #expect(written.byteCount == 8)
    }

    @Test("A stream that fails removes its file, and what it reports afterwards changes nothing")
    func failedStreamRemovesItsFile() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(throws: StreamFailure.self) {
            try await AttachmentFileWriter.copy(to: url) { handler in
                handler(Data("partial".utf8), nil, false)
                handler(nil, StreamFailure(), false)
                // HealthKit reporting more after a failure must not resume the copy a second time.
                handler(nil, nil, true)
                return Progress(totalUnitCount: 1)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Cancelling the task cancels a stream that is still waiting, and removes its file")
    func cancellationEndsAWaitingStream() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let progress = Progress(totalUnitCount: 1)
        let started = AsyncStream<Void>.makeStream()
        let copy = Task {
            try await AttachmentFileWriter.copy(to: url) { handler in
                // Like an attachment HealthKit is still downloading from iCloud: one chunk, then nothing.
                handler(Data("first".utf8), nil, false)
                started.continuation.yield()
                return progress
            }
        }
        for await _ in started.stream {
            break
        }
        copy.cancel()
        await #expect(throws: CancellationError.self) {
            try await copy.value
        }
        #expect(progress.isCancelled)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A task cancelled before the stream starts never starts it")
    func cancellationBeforeTheStreamStarts() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let copy = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AttachmentFileWriter.copy(to: url) { _ in
                Issue.record("A cancelled task started a stream")
                return Progress(totalUnitCount: 1)
            }
        }
        await #expect(throws: CancellationError.self) {
            try await copy.value
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A directory already at the location makes the copy fail and stays, with everything in it")
    func existingDirectoryIsNeverRemoved() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let inside = url.appendingPathComponent("keep", isDirectory: false)
        try Data("not the copy's to remove".utf8).write(to: inside)
        await #expect(throws: (any Error).self) {
            try await AttachmentFileWriter.copy(to: url) { _ in
                Issue.record("A copy that couldn't create its file started a stream")
                return Progress(totalUnitCount: 1)
            }
        }
        #expect(try Data(contentsOf: inside) == Data("not the copy's to remove".utf8))
    }

    @Test("A file already at the location is replaced, not appended to")
    func existingFileIsReplaced() throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("a stale copy from an earlier attempt".utf8).write(to: url)
        let writer = try AttachmentFileWriter(url: url)
        try writer.append(Data("new".utf8))
        let written = try writer.finish()
        #expect(try Data(contentsOf: url) == Data("new".utf8))
        #expect(written.byteCount == 3)
    }
}

#endif
