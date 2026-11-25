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
