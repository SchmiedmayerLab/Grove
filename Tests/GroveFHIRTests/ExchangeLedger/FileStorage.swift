//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import GroveFHIRContract


/// A single-file storage per the contract's backend table: the map is a binary property list rewritten
/// atomically through a synced temporary file and a rename, serialised by a process lock and by `flock` on a
/// sibling lock file that is never replaced.
final class FileStorage: ExchangeProducer.Storage, @unchecked Sendable { // The file is guarded by `lock` and `flock`.
    struct IOFailure: Error, Equatable {
        let operation: String
    }

    private final class Snapshot: ExchangeProducer.Transaction {
        var entries: [String: Data]
        var changed = false

        init(entries: [String: Data]) {
            self.entries = entries
        }

        func read(_ key: String) throws -> Data? {
            entries[key]
        }

        func write(_ value: Data, for key: String) throws {
            entries[key] = value
            changed = true
        }

        func remove(_ key: String) throws {
            if entries.removeValue(forKey: key) != nil {
                changed = true
            }
        }

        func keys(prefixedBy prefix: String) throws -> [String] {
            entries.keys.filter { $0.hasPrefix(prefix) }
        }
    }

    let directory: URL
    private let lock = NSLock()

    private var ledgerURL: URL { directory.appendingPathComponent("ledger.plist") }
    private var lockURL: URL { directory.appendingPathComponent("ledger.lock") }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Flushes the file to stable storage; on Darwin that takes `F_FULLFSYNC`, as `fsync` leaves the device cache.
    private static func synchronize(_ descriptor: Int32) -> Bool {
        #if canImport(Darwin)
        fcntl(descriptor, F_FULLFSYNC) == 0
        #else
        fsync(descriptor) == 0
        #endif
    }

    func transaction<R>(_ body: (any ExchangeProducer.Transaction) throws -> R) throws -> R {
        lock.lock()
        defer {
            lock.unlock()
        }
        let lockDescriptor = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard lockDescriptor >= 0 else {
            throw IOFailure(operation: "open lock")
        }
        defer {
            close(lockDescriptor)
        }
        guard flock(lockDescriptor, LOCK_EX) == 0 else {
            throw IOFailure(operation: "flock")
        }
        defer {
            flock(lockDescriptor, LOCK_UN)
        }
        let snapshot = Snapshot(entries: try load())
        let result = try body(snapshot)
        if snapshot.changed {
            try store(snapshot.entries)
        }
        return result
    }

    private func load() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: ledgerURL.path) else {
            return [:]
        }
        return try PropertyListDecoder().decode([String: Data].self, from: Data(contentsOf: ledgerURL))
    }

    private func store(_ entries: [String: Data]) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let bytes = try encoder.encode(entries)
        let temporaryURL = directory.appendingPathComponent("ledger.plist.tmp")
        let descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else {
            throw IOFailure(operation: "open temporary")
        }
        let written = bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map { write(descriptor, $0, buffer.count) } ?? 0
        }
        guard written == bytes.count, Self.synchronize(descriptor) else {
            close(descriptor)
            throw IOFailure(operation: "write temporary")
        }
        close(descriptor)
        guard rename(temporaryURL.path, ledgerURL.path) == 0 else {
            throw IOFailure(operation: "rename")
        }
        let directoryDescriptor = open(directory.path, O_RDONLY)
        guard directoryDescriptor >= 0 else {
            throw IOFailure(operation: "open directory")
        }
        defer {
            close(directoryDescriptor)
        }
        guard fsync(directoryDescriptor) == 0 else {
            throw IOFailure(operation: "sync directory")
        }
    }
}
