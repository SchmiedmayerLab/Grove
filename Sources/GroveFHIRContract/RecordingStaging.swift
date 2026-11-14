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


/// Owns only the short creation window before a staged file becomes anonymous.
///
/// The directory lock serializes creation and recovery across processes. Data is written only
/// after unlinking, so crash recovery can encounter only empty abandoned creation files. It never
/// removes nonempty files, links, unknown names, or directories. Active readers have no named files.
enum RecordingStaging {
    private typealias FileError = RecordingFile.FileError
    private static let prefix = ".stage-"

    static func create() throws -> RecordingFile.Storage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-recording-staging-v1", isDirectory: true)
        return try create(in: root)
    }

    static func create(in root: URL) throws -> RecordingFile.Storage {
        if mkdir(root.path, 0o700) != 0, errno != EEXIST { throw FileError.stagingUnavailable }
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw FileError.stagingUnavailable }
        defer { close(directory) }
        try verify(directory, kind: mode_t(S_IFDIR), permissions: 0o700)
        let lock = try openLock(in: directory)
        defer { close(lock) }
        try verify(lock, kind: mode_t(S_IFREG), permissions: 0o600)
        while flock(lock, LOCK_EX) != 0 {
            if errno != EINTR { throw FileError.stagingUnavailable }
            try Task.checkCancellation()
        }
        defer { flock(lock, LOCK_UN) }
        try recover(in: root, descriptor: directory)
        let name = prefix + UUID().uuidString.lowercased()
        let descriptor = openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw FileError.stagingUnavailable }
        let storage = RecordingFile.Storage(descriptor: descriptor)
        guard unlinkat(directory, name, 0) == 0 else { throw FileError.stagingUnavailable }
        return storage
    }

    private static func openLock(in directory: Int32) throws -> Int32 {
        // Separate exclusive creation from opening the established lock. Concurrent O_CREAT opens
        // can fail with ENOENT on Darwin even when another creator has made the file available.
        let flags = O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let created = openat(directory, ".lock", flags | O_CREAT | O_EXCL, 0o600)
        if created >= 0 {
            return created
        }
        guard errno == EEXIST else { throw FileError.stagingUnavailable }
        let existing = openat(directory, ".lock", flags)
        guard existing >= 0 else { throw FileError.stagingUnavailable }
        return existing
    }

    private static func verify(_ descriptor: Int32, kind: mode_t, permissions: mode_t) throws {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & mode_t(S_IFMT) == kind,
              attributes.st_mode & 0o777 == permissions,
              attributes.st_uid == geteuid(),
              kind != mode_t(S_IFREG) || attributes.st_nlink == 1 else {
            throw FileError.stagingUnavailable
        }
    }

    private static func recover(in root: URL, descriptor: Int32) throws {
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: root.path) } catch { throw FileError.stagingUnavailable }
        for name in names where isCreationFile(name) {
            var attributes = stat()
            guard fstatat(descriptor, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0,
                  attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  attributes.st_mode & 0o777 == 0o600,
                  attributes.st_uid == geteuid(), attributes.st_nlink == 1, attributes.st_size == 0 else { continue }
            guard unlinkat(descriptor, name, 0) == 0 else { throw FileError.stagingUnavailable }
        }
    }

    private static func isCreationFile(_ name: String) -> Bool {
        guard name.hasPrefix(prefix), let identifier = UUID(uuidString: String(name.dropFirst(prefix.count))) else {
            return false
        }
        return name == prefix + identifier.uuidString.lowercased()
    }
}
