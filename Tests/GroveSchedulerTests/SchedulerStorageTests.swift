//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers
@testable import GroveScheduler
import Testing


/// Covers bringing a scheduler store forward from either predecessor layout.
@Suite
struct SchedulerStorageTests {
    private static let legacyStore = "edu.stanford.spezi.scheduler.storage.sqlite"
    // From the vault, not a literal: this names a directory on real devices and a rename must never move it.
    private static let legacyDirectory = LegacyStorage.schedulerDirectory
    private static let marker = "didPerformIOS26Migration"

    private let fileManager = FileManager.default

    private func writeStore(in directory: URL, contents: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try "\(contents)\(suffix)".write(
                to: directory.appendingPathComponent(Self.legacyStore + suffix),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    /// Gives each test its own destination and its own stand-in for the documents directory, so a
    /// test never reads or writes the developer's real `~/Documents`.
    private func withDirectories(_ body: (_ destination: URL, _ legacyRoot: URL) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let legacyRoot = root.appendingPathComponent("Documents")
        try? fileManager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try body(root.appendingPathComponent("Support/Scheduler"), legacyRoot)
    }

    private func storeContents(at store: URL) throws -> String {
        try String(contentsOf: store, encoding: .utf8)
    }

    @Test
    func aFreshInstallJustGetsItsDirectory() throws {
        try withDirectories { destination, legacyRoot in
            let store = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(store == destination.appendingPathComponent("store.sqlite"))
            #expect(fileManager.fileExists(atPath: destination.path))
            #expect(!fileManager.fileExists(atPath: store.path))
        }
    }

    /// The layout 0.1.x shipped: a `SpeziScheduler` directory inside `Documents`.
    @Test
    func bringsForwardTheDirectoryLayout() throws {
        try withDirectories { destination, legacyRoot in
            let legacy = legacyRoot.appendingPathComponent(Self.legacyDirectory)
            try writeStore(in: legacy, contents: "current")

            let store = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(try storeContents(at: store) == "current")
            #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("store.sqlite-wal").path))
            #expect(!fileManager.fileExists(atPath: legacy.appendingPathComponent(Self.legacyStore).path))
        }
    }

    /// The layout before that: loose files directly in `Documents`.
    @Test
    func bringsForwardTheLooseDocumentsLayout() throws {
        try withDirectories { destination, legacyRoot in
            try writeStore(in: legacyRoot, contents: "ancient")

            let store = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(try storeContents(at: store) == "ancient")
            #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent(Self.legacyStore).path))
        }
    }

    /// A 0.1.x install interrupted part-way through its own migration carries both. The newer wins.
    @Test
    func prefersTheNewerLayoutWhenBothExist() throws {
        try withDirectories { destination, legacyRoot in
            try writeStore(in: legacyRoot, contents: "ancient")
            try writeStore(in: legacyRoot.appendingPathComponent(Self.legacyDirectory), contents: "current")

            let store = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(try storeContents(at: store) == "current")
        }
    }

    /// Leaving the marker behind re-runs the iOS 26 migration against migrated rows, which traps on launch.
    @Test
    func theIOS26MarkerTravelsWithTheStore() throws {
        try withDirectories { destination, legacyRoot in
            let legacy = legacyRoot.appendingPathComponent(Self.legacyDirectory)
            try writeStore(in: legacy, contents: "current")
            try "".write(to: legacy.appendingPathComponent(Self.marker), atomically: true, encoding: .utf8)

            Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot)

            #expect(fileManager.fileExists(atPath: destination.appendingPathComponent(Self.marker).path))
        }
    }

    /// A device that never ran an iOS 26 build has no marker, and must not be given one — it still
    /// needs that migration.
    @Test
    func anAbsentIOS26MarkerIsNotInvented() throws {
        try withDirectories { destination, legacyRoot in
            try writeStore(in: legacyRoot.appendingPathComponent(Self.legacyDirectory), contents: "current")

            Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot)

            #expect(!fileManager.fileExists(atPath: destination.appendingPathComponent(Self.marker).path))
        }
    }

    @Test
    func isIdempotentAcrossLaunches() throws {
        try withDirectories { destination, legacyRoot in
            try writeStore(in: legacyRoot.appendingPathComponent(Self.legacyDirectory), contents: "current")

            let first = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))
            let second = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(first == second)
            #expect(try storeContents(at: second) == "current")
        }
    }

    /// Downgrade-then-upgrade: 0.1.x recreated a store in Documents while the new location already
    /// holds the real one. The new location must win.
    @Test
    func anExistingStoreIsNotOverwrittenByAResurrectedLegacyOne() throws {
        try withDirectories { destination, legacyRoot in
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try "authoritative".write(
                to: destination.appendingPathComponent("store.sqlite"),
                atomically: true,
                encoding: .utf8
            )
            try writeStore(in: legacyRoot.appendingPathComponent(Self.legacyDirectory), contents: "stale")

            let store = try #require(Scheduler.prepareStorage(in: destination, migratingFrom: legacyRoot))

            #expect(try storeContents(at: store) == "authoritative")
        }
    }
}
