//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Moves a SQLite-backed store to a new location without risking it.
///
/// A store is several files — the database plus its `-wal`, `-shm` and `-journal` sidecars, and for
/// Core Data a `.<name>_SUPPORT` directory. Moving them one at a time is not recoverable: a process
/// killed part-way leaves a database whose write-ahead log is elsewhere, or a fresh empty database
/// beside a log belonging to a different one. Neither is detectable afterwards.
///
/// So the whole set is copied into a staging directory first and only then swapped into place. The
/// database is always the last thing to land, so until the move is complete the destination does not
/// look like a store and the next launch retries instead of adopting a fragment.
///
/// ## Topics
///
/// ### Relocating a store
/// - ``relocate(storeNamed:from:to:renamedTo:alongside:fileManager:)``
/// - ``Outcome``
///
/// ### Relocating a directory
/// - ``relocateDirectory(from:to:fileManager:)``
/// - ``renameChildren(matching:in:fileManager:didRename:)``
public enum StoreRelocation {
    /// What a relocation attempt did.
    public enum Outcome: Hashable, Sendable {
        /// The store was staged and committed at the destination.
        case relocated
        /// The destination already held a store; the source was left alone.
        case destinationAlreadyPopulated
        /// There was nothing at the source to relocate.
        case nothingToRelocate
    }

    /// A relocation that could not be completed safely.
    public enum Failure: Error, CustomStringConvertible {
        /// The move reported success but the destination does not hold the database.
        case destinationIncomplete(String)

        public var description: String {
            switch self {
            case .destinationIncomplete(let name):
                "Relocation finished without leaving '\(name)' at the destination."
            }
        }
    }

    /// Suffixes a SQLite store's sidecar files carry.
    private static let sidecarSuffixes = ["-wal", "-shm", "-journal"]

    /// Relocates a store and every file belonging to it.
    ///
    /// Safe to call on every launch: it is a no-op once the destination holds a store.
    ///
    /// - Parameters:
    ///   - storeName: The database's file name, e.g. `store.sqlite`. Sidecars are derived from it.
    ///   - sourceDirectory: The directory the store lives in today.
    ///   - destinationDirectory: The directory it should live in. Created if needed.
    ///   - newStoreName: A name to give the database at the destination. Sidecars follow it.
    ///   - companions: Names of further files beside the store that belong with it, moved when
    ///     present. Absence is never synthesized — a marker missing at the source stays missing.
    ///   - fileManager: The file manager to operate through.
    /// - Returns: What the attempt did.
    /// - Throws: If the store exists at the source but could not be relocated. The source is intact,
    ///     and the destination is left without a database so the next attempt retries.
    @discardableResult
    public static func relocate(
        storeNamed storeName: String,
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        renamedTo newStoreName: String? = nil,
        alongside companions: [String] = [],
        fileManager: FileManager = .default
    ) throws -> Outcome {
        let destinationName = newStoreName ?? storeName
        // Presence of the *database* decides, not presence of the directory: an interrupted attempt
        // can leave a lone sidecar behind, and treating that as "already done" would strand the store.
        guard !fileManager.fileExists(atPath: destinationDirectory.appendingPathComponent(destinationName).path) else {
            return .destinationAlreadyPopulated
        }
        guard fileManager.fileExists(atPath: sourceDirectory.appendingPathComponent(storeName).path) else {
            return .nothingToRelocate
        }

        var moves = try storeFiles(named: storeName, in: sourceDirectory, fileManager: fileManager).map { source in
            (source, renaming(source.lastPathComponent, from: storeName, to: destinationName))
        }
        moves += companions
            .map { (sourceDirectory.appendingPathComponent($0), $0) }
            .filter { fileManager.fileExists(atPath: $0.0.path) }
        // Renaming a store in place makes source and destination the same file for anything whose name
        // does not change. Copying a file onto itself would destroy it.
        moves = moves.filter { $0.0.standardizedFileURL != destinationDirectory.appendingPathComponent($0.1).standardizedFileURL }

        let parent = destinationDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try removeStaleStaging(for: destinationDirectory, in: parent, fileManager: fileManager)

        let staging = parent.appendingPathComponent(stagingPrefix(for: destinationDirectory) + UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (source, name) in moves {
                try fileManager.copyItem(at: source, to: staging.appendingPathComponent(name))
            }
            if fileManager.fileExists(atPath: destinationDirectory.path) {
                try swap(from: staging, into: destinationDirectory, storeNamed: destinationName, fileManager: fileManager)
                try? fileManager.removeItem(at: staging)
            } else {
                // Nothing at the destination yet, so the whole set commits with one atomic rename.
                try fileManager.moveItem(at: staging, to: destinationDirectory)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        // Never report success without the database actually being there: a source directory that
        // cannot be enumerated, or a filter that matched nothing, would otherwise look like a
        // completed migration and permanently strand the real store.
        guard fileManager.fileExists(atPath: destinationDirectory.appendingPathComponent(destinationName).path) else {
            throw Failure.destinationIncomplete(destinationName)
        }

        // Only now is the destination authoritative, so losing this leaves a harmless duplicate.
        for (source, _) in moves {
            try? fileManager.removeItem(at: source)
        }
        return .relocated
    }

    /// Moves a whole directory to a new location, in one atomic rename.
    ///
    /// For state that is a directory rather than a store — downloaded bundles, a nest of loose
    /// entries. Safe to call on every launch.
    ///
    /// A directory already at the destination is authoritative and the source is left untouched: a
    /// downgrade to an older release and back can recreate the legacy directory, and adopting it
    /// would silently roll the user back.
    ///
    /// - Parameters:
    ///   - sourceDirectory: The directory as it exists today.
    ///   - destinationDirectory: Where it should be. Its parent is created if needed.
    ///   - fileManager: The file manager to operate through.
    /// - Returns: What the attempt did.
    /// - Throws: If the source exists but could not be moved. The source is intact.
    @discardableResult
    public static func relocateDirectory(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> Outcome {
        guard !fileManager.fileExists(atPath: destinationDirectory.path) else {
            return .destinationAlreadyPopulated
        }
        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            return .nothingToRelocate
        }
        try fileManager.createDirectory(
            at: destinationDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: sourceDirectory, to: destinationDirectory)
        return .relocated
    }

    /// Renames the children of a directory whose names begin with a superseded prefix.
    ///
    /// Children are moved verbatim — nothing is decoded — so this is safe for encrypted payloads
    /// whose ciphertext does not depend on the file name. A child already present under its new name
    /// wins, and the stale one is left in place rather than deleted.
    ///
    /// - Parameters:
    ///   - renames: Superseded prefix to current prefix. Applied longest-first, so a prefix that is
    ///     itself the prefix of another cannot shadow it.
    ///   - directory: The directory whose children are renamed.
    ///   - fileManager: The file manager to operate through.
    ///   - didRename: Called with each superseded prefix that matched at least one child.
    public static func renameChildren(
        matching renames: [(legacy: String, current: String)],
        in directory: URL,
        fileManager: FileManager = .default,
        didRename: (String) -> Void = { _ in }
    ) throws {
        let ordered = renames.sorted { $0.legacy.count > $1.legacy.count }
        for child in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            guard let rename = ordered.first(where: { child.hasPrefix($0.legacy) }) else {
                continue
            }
            let source = directory.appendingPathComponent(child)
            let destination = directory.appendingPathComponent(rename.current + child.dropFirst(rename.legacy.count))
            guard !isOccupiedByAnother(destination, than: source, fileManager: fileManager) else {
                continue
            }
            try fileManager.moveItem(at: source, to: destination)
            didRename(rename.legacy)
        }
    }

    /// Every file belonging to a store: the database, its sidecars, and any Core Data support directory.
    ///
    /// Matched exactly rather than by prefix. A bare prefix match would sweep in an unrelated
    /// `<store>.backup`, and — when a store is renamed to something that prefixes its old name —
    /// would treat the files being copied as orphans to delete.
    static func storeFiles(named storeName: String, in directory: URL, fileManager: FileManager = .default) throws -> [URL] {
        let supportDirectory = ".\(storeName)_SUPPORT"
        let belongs = { (name: String) in
            name == storeName || name == supportDirectory || sidecarSuffixes.contains { name == storeName + $0 }
        }
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter(belongs)
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Swaps a staged store into a destination directory that already exists.
    ///
    /// Everything is copied before anything is replaced, and the database lands last, so an
    /// interruption leaves the destination without a database and the next launch retries.
    private static func swap(
        from staging: URL,
        into destinationDirectory: URL,
        storeNamed storeName: String,
        fileManager: FileManager
    ) throws {
        let staged = try fileManager.contentsOfDirectory(atPath: staging.path)
        // Explicit partition: a comparator that ignores its right operand is not a strict weak
        // ordering, so `sorted` would not actually guarantee the database goes last.
        for name in staged.filter({ $0 != storeName }) + staged.filter({ $0 == storeName }) {
            let destination = destinationDirectory.appendingPathComponent(name)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: staging.appendingPathComponent(name), to: destination)
        }
    }

    /// Removes staging directories abandoned by an earlier interrupted attempt.
    ///
    /// A staging directory that still exists was never committed, so discarding it is safe by
    /// construction — and leaving them would accumulate a full copy of the store on every failure.
    private static func removeStaleStaging(for destinationDirectory: URL, in parent: URL, fileManager: FileManager) throws {
        let prefix = stagingPrefix(for: destinationDirectory)
        for child in (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? [] where child.hasPrefix(prefix) {
            try? fileManager.removeItem(at: parent.appendingPathComponent(child))
        }
    }

    private static func stagingPrefix(for destinationDirectory: URL) -> String {
        ".\(destinationDirectory.lastPathComponent).staging-"
    }

    /// Whether `destination` is taken by a file that is not `source`.
    ///
    /// A plain existence check is wrong on a case-insensitive volume — the default on macOS — where a
    /// rename differing only in case reports the destination as occupied by the very file being moved,
    /// and the rename is silently skipped. Comparing file identity distinguishes that from a genuine
    /// collision, and stays correct on case-sensitive volumes where the two really are different files.
    private static func isOccupiedByAnother(_ destination: URL, than source: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: destination.path) else {
            return false
        }
        let identity = { (url: URL) in
            (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        }
        guard let destinationIdentity = identity(destination), let sourceIdentity = identity(source) else {
            return true
        }
        return !destinationIdentity.isEqual(sourceIdentity)
    }

    /// Maps a store file's name onto a renamed store, preserving its sidecar suffix.
    private static func renaming(_ fileName: String, from storeName: String, to newStoreName: String) -> String {
        if fileName == ".\(storeName)_SUPPORT" {
            return ".\(newStoreName)_SUPPORT"
        }
        guard fileName.hasPrefix(storeName) else {
            return fileName
        }
        return newStoreName + fileName.dropFirst(storeName.count)
    }
}
