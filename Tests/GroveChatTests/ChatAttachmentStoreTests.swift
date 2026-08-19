//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveChat
import Testing


private final class Fixture {
    let directory: URL
    let source: URL
    let store: ChatAttachmentStore

    init(
        cleanupPolicy: ChatAttachmentStore.CleanupPolicy = .never,
        maximumFileSize: Int = 20 * 1024 * 1024
    ) throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        directory = root.appendingPathComponent("attachments", isDirectory: true)
        source = root.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source)
        store = ChatAttachmentStore(
            storage: FileSystemChatAttachmentStorage(directory: directory),
            cleanupPolicy: cleanupPolicy,
            maximumFileSize: maximumFileSize
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}


/// Covers app-owned attachment copies and their retention lifecycle.
@Suite("Chat Attachment Store")
struct ChatAttachmentStoreTests {
    @Test("The default directory is app-scoped without a framework-branded component")
    func defaultDirectoryIsUnbranded() {
        #expect(FileSystemChatAttachmentStorage.defaultDirectory.lastPathComponent == "ChatAttachments")
    }

    @Test("The default policy keeps attachments until explicit removal")
    func defaultCleanupPolicyIsNever() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let storage = FileSystemChatAttachmentStorage(directory: fixture.directory)
        let stored = try storage.store(fileAt: fixture.source)

        let newSession = ChatAttachmentStore(storage: storage)

        #expect(try newSession.attachments == [stored])
    }

    @Test("A picked file is copied somewhere the app owns and can be enumerated")
    func storingCopiesTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }

        let stored = try fixture.store.store(fileAt: fixture.source)

        #expect(stored.name == fixture.source.lastPathComponent)
        #expect(stored.url != fixture.source, "the conversation must not depend on the picker's own URL")
        #expect(try Data(contentsOf: stored.url) == Data("hello".utf8))
        #expect(try fixture.store.attachments == [stored])

        // Deleting what the picker offered leaves the conversation's copy intact.
        try FileManager.default.removeItem(at: fixture.source)
        #expect(FileManager.default.fileExists(atPath: stored.url.path))
    }

    @Test("One attachment or every attachment can be removed explicitly")
    func explicitRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let first = try fixture.store.store(fileAt: fixture.source)

        try fixture.store.remove(first)
        #expect(try fixture.store.attachments.isEmpty)

        _ = try fixture.store.store(fileAt: fixture.source)
        try fixture.store.removeAll()
        #expect(try fixture.store.attachments.isEmpty)
    }

    @Test("The launch policy clears attachments from a prior session")
    func launchCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let storage = FileSystemChatAttachmentStorage(directory: fixture.directory)
        _ = try storage.store(fileAt: fixture.source)

        let newSession = ChatAttachmentStore(storage: storage, cleanupPolicy: .onLaunch)

        #expect(try newSession.attachments.isEmpty)
    }

    @Test("Age-based cleanup removes only expired attachments")
    func ageBasedCleanup() throws {
        let fixture = try Fixture(cleanupPolicy: .olderThan(60))
        defer { fixture.removeFiles() }
        let storage = FileSystemChatAttachmentStorage(directory: fixture.directory)
        let old = try storage.store(fileAt: fixture.source)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: old.url.deletingLastPathComponent().path
        )

        let freshSource = fixture.directory.deletingLastPathComponent().appendingPathComponent("fresh.txt")
        try Data("fresh".utf8).write(to: freshSource)
        let fresh = try storage.store(fileAt: freshSource)

        let retained = try fixture.store.attachments

        #expect(retained == [fresh])
        #expect(!FileManager.default.fileExists(atPath: old.url.path))
    }

    @Test("A file too large to send is refused, with the reason")
    func oversizeFilesAreRefused() throws {
        let fixture = try Fixture(maximumFileSize: 1)
        defer { fixture.removeFiles() }

        #expect(throws: ChatAttachmentStore.StoreError.self) {
            try fixture.store.store(fileAt: fixture.source)
        }

        do {
            _ = try fixture.store.store(fileAt: fixture.source)
        } catch let error as ChatAttachmentStore.StoreError {
            let described = try #require(error.errorDescription)
            #expect(described.contains("limit"), "the user has to learn why, got \(described)")
        }
    }

    @Test("A file right at the ceiling is still accepted")
    func filesAtTheCeilingAreAccepted() throws {
        let fixture = try Fixture(maximumFileSize: Data("hello".utf8).count)
        defer { fixture.removeFiles() }

        let stored = try fixture.store.store(fileAt: fixture.source)

        #expect(stored.name == fixture.source.lastPathComponent, "the ceiling is inclusive")
    }
}
