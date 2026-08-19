//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Grove
import GroveFoundation
public import Observation
import OSLog
import Synchronization
import UniformTypeIdentifiers


/// A persistence backend for files attached to a chat.
///
/// Implement this protocol to mirror attachments into an encrypted store, an app group, or another app-owned
/// location. ``ChatAttachmentStore`` serializes calls to its backend.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol ChatAttachmentStorage: Sendable {
    /// Copies a picked file into storage and returns the app-owned copy.
    func store(fileAt source: URL) throws -> ChatEntity.Content.File
    /// Every attachment currently in storage.
    func attachments() throws -> [ChatEntity.Content.File]
    /// Removes one attachment.
    func remove(_ attachment: ChatEntity.Content.File) throws
    /// Removes every attachment.
    func removeAll() throws
    /// Removes attachments stored before the given date.
    func removeAttachments(storedBefore date: Date) throws
}


/// Stores chat attachments in an app-owned directory on disk.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct FileSystemChatAttachmentStorage: ChatAttachmentStorage, Sendable {
    /// The default Application Support directory for chat attachments.
    public static var defaultDirectory: URL {
        (try? StorageNamespace.app.directory(.chatAttachments))
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ChatAttachments", isDirectory: true)
    }

    /// The directory containing the app-owned attachment copies.
    public let directory: URL

    /// Creates file-system attachment storage.
    ///
    /// - Parameter directory: The directory to use. By default, attachments live in Application Support.
    public init(directory: URL = Self.defaultDirectory) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func attachment(at url: URL) -> ChatEntity.Content.File {
        ChatEntity.Content.File(
            name: url.lastPathComponent,
            url: url,
            contentTypeIdentifier: (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier
        )
    }

    public func store(fileAt source: URL) throws -> ChatEntity.Content.File {
        let root = try prepareDirectory()
        let destinationDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        do {
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            return Self.attachment(at: destination)
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectory)
            throw error
        }
    }

    public func attachments() throws -> [ChatEntity.Content.File] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try storedDirectories().compactMap { storedDirectory in
            let file = try FileManager.default.contentsOfDirectory(
                at: storedDirectory,
                includingPropertiesForKeys: [.contentTypeKey],
                options: [.skipsHiddenFiles]
            )
            .first
            guard let file else {
                return nil
            }
            // FileManager may resolve a symlinked ancestor while enumerating (for example `/var` to `/private/var`).
            // Reconstruct the URL from the configured root so a stored attachment retains stable value identity.
            let stableURL = directory
                .appendingPathComponent(storedDirectory.lastPathComponent, isDirectory: true)
                .appendingPathComponent(file.lastPathComponent)
            return Self.attachment(at: stableURL)
        }
    }

    public func remove(_ attachment: ChatEntity.Content.File) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let file = attachment.url.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let storedDirectory = file.deletingLastPathComponent()
        guard storedDirectory.deletingLastPathComponent() == root else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: storedDirectory.path) {
            try FileManager.default.removeItem(at: storedDirectory)
        }
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func removeAttachments(storedBefore date: Date) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        for storedDirectory in try storedDirectories() {
            let values = try storedDirectory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let storedAt = values.contentModificationDate ?? values.creationDate ?? .distantPast
            if storedAt < date {
                try FileManager.default.removeItem(at: storedDirectory)
            }
        }
    }

    private func prepareDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory.resolvingSymlinksInPath()
    }

    private func storedDirectories() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}


/// Owns the lifecycle of files attached to chats.
///
/// Configure this module to clean up sensitive attachments predictably and make its storage available to the chat
/// composer. The default policy keeps attachments until the app removes them explicitly. Apps can instead choose
/// launch- or age-based cleanup, or provide their own ``ChatAttachmentStorage``.
///
/// ```swift
/// ChatAttachmentStore(cleanupPolicy: .olderThan(7 * 24 * 60 * 60))
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class ChatAttachmentStore: Module, DefaultInitializable, EnvironmentAccessible, Sendable {
    /// When automatically retained attachments are removed.
    public enum CleanupPolicy: Hashable, Sendable {
        /// Remove attachments left by a previous app session during module configuration or first use.
        case onLaunch
        /// Remove attachments older than the given number of seconds.
        case olderThan(TimeInterval)
        /// Keep attachments until the app removes them explicitly.
        case never
    }

    /// What can go wrong while taking an app-owned copy of a picked file.
    public enum StoreError: LocalizedError {
        /// The file could not be reached, which is what a revoked security scope looks like.
        case notAccessible
        /// The file is larger than a conversation can carry.
        case tooLarge(size: Int, maximum: Int)

        public var errorDescription: String? {
            switch self {
            case .notAccessible:
                String(localized: "ATTACHMENT_NOT_ACCESSIBLE", bundle: .module)
            case let .tooLarge(size, maximum):
                String(
                    localized: "ATTACHMENT_TOO_LARGE \(size.formatted(.byteCount(style: .file))) \(maximum.formatted(.byteCount(style: .file)))",
                    bundle: .module
                )
            }
        }
    }

    private static let logger = Logger(subsystem: "org.grovealliance", category: "GroveChatAttachments")
    static let fallback = ChatAttachmentStore()

    /// The kinds of file a chat accepts unless it says otherwise.
    static var defaultContentTypes: [UTType] {
        [
            .pdf, .plainText, .text, .rtf, .image, .spreadsheet, .presentation, .epub,
            UTType("com.microsoft.word.doc"), UTType("org.openxmlformats.wordprocessingml.document")
        ].compactMap { $0 }
    }

    /// The largest file a conversation will carry.
    public let maximumFileSize: Int
    /// The policy applied during module configuration or first use.
    public let cleanupPolicy: CleanupPolicy

    @ObservationIgnored private let storage: any ChatAttachmentStorage
    @ObservationIgnored private let isPrepared = Mutex(false)

    /// Every attachment currently managed by this store.
    public var attachments: [ChatEntity.Content.File] {
        get throws {
            try withPreparedStorage { try storage.attachments() }
        }
    }

    /// Creates the default attachment store.
    public convenience init() {
        self.init(storage: FileSystemChatAttachmentStorage())
    }

    /// Creates a file-system attachment store with a cleanup policy.
    public convenience init(
        cleanupPolicy: CleanupPolicy,
        directory: URL = FileSystemChatAttachmentStorage.defaultDirectory,
        maximumFileSize: Int = 20 * 1024 * 1024
    ) {
        self.init(
            storage: FileSystemChatAttachmentStorage(directory: directory),
            cleanupPolicy: cleanupPolicy,
            maximumFileSize: maximumFileSize
        )
    }

    /// Creates a configurable attachment store.
    ///
    /// - Parameters:
    ///   - storage: Where app-owned attachment copies live.
    ///   - cleanupPolicy: When old attachments are removed. Defaults to keeping them until explicit removal.
    ///   - maximumFileSize: The largest accepted source file, in bytes.
    public init(
        storage: any ChatAttachmentStorage,
        cleanupPolicy: CleanupPolicy = .never,
        maximumFileSize: Int = 20 * 1024 * 1024
    ) {
        if case .olderThan(let interval) = cleanupPolicy {
            precondition(interval >= 0, "Chat attachment retention cannot be negative.")
        }
        precondition(maximumFileSize > 0, "Chat attachment maximum file size must be positive.")
        self.storage = storage
        self.cleanupPolicy = cleanupPolicy
        self.maximumFileSize = maximumFileSize
    }

    public func configure() {
        do {
            try prepareIfNeeded()
        } catch {
            Self.logger.error("Unable to clean up chat attachments: \(error)")
        }
    }

    /// Copies a picked file into app-owned storage and describes the copy.
    public func store(fileAt source: URL) throws -> ChatEntity.Content.File {
        let isScoped = source.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize {
            throw StoreError.tooLarge(size: size, maximum: maximumFileSize)
        }
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw StoreError.notAccessible
        }
        return try withPreparedStorage {
            try storage.store(fileAt: source)
        }
    }

    /// Removes one managed attachment.
    public func remove(_ attachment: ChatEntity.Content.File) throws {
        try withPreparedStorage {
            try storage.remove(attachment)
        }
    }

    /// Removes every managed attachment.
    public func removeAll() throws {
        try withPreparedStorage {
            try storage.removeAll()
        }
    }

    /// Applies ``cleanupPolicy`` immediately.
    public func cleanup() throws {
        try isPrepared.withLock { isPrepared in
            try applyCleanupPolicy()
            isPrepared = true
        }
    }

    private func prepareIfNeeded() throws {
        try isPrepared.withLock { isPrepared in
            guard !isPrepared else {
                return
            }
            try applyCleanupPolicy()
            isPrepared = true
        }
    }

    private func withPreparedStorage<Result>(_ operation: () throws -> Result) throws -> Result {
        try isPrepared.withLock { isPrepared in
            if !isPrepared {
                try applyCleanupPolicy()
                isPrepared = true
            }
            return try operation()
        }
    }

    private func applyCleanupPolicy() throws {
        switch cleanupPolicy {
        case .onLaunch:
            try storage.removeAll()
        case .olderThan(let interval):
            try storage.removeAttachments(storedBefore: Date(timeIntervalSinceNow: -interval))
        case .never:
            break
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StorageNamespace.Component {
    /// Where chat attachments live inside the consuming app's storage namespace.
    fileprivate static let chatAttachments = Self("ChatAttachments")
}
