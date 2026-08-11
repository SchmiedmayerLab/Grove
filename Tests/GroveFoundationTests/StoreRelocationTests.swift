//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFoundation
import Testing


/// Fails the nth file operation, standing in for the process dying at that point.
private final class FailingFileManager: FileManager, @unchecked Sendable {
    struct Stop: Error {}

    private var remaining: Int

    var operationsPerformed: Int { budget - remaining }
    private let budget: Int

    init(failingAfter operations: Int) {
        self.budget = operations
        self.remaining = operations
        super.init()
    }

    private func consume() throws {
        guard remaining > 0 else {
            throw Stop()
        }
        remaining -= 1
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try consume()
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try consume()
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        try consume()
        try super.removeItem(at: URL)
    }
}


@Suite
struct StoreRelocationTests {
    private static let storeName = "store.sqlite"
    private static let files = ["store.sqlite", "store.sqlite-wal", "store.sqlite-shm", ".store.sqlite_SUPPORT"]

    private func makeStore(in directory: URL, contents: String = "data") throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in Self.files {
            if name.hasSuffix("_SUPPORT") {
                try fileManager.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
            } else {
                try "\(contents):\(name)".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
    }

    private func storeIsComplete(in directory: URL) -> Bool {
        Self.files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test
    func relocatesEveryFileIncludingTheSupportDirectory() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Documents/Legacy")
            let destination = root.appendingPathComponent("Application Support/app/Scheduler")
            try makeStore(in: source)

            let outcome = try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)

            #expect(outcome == .relocated)
            #expect(storeIsComplete(in: destination))
            #expect(try StoreRelocation.storeFiles(named: Self.storeName, in: source).isEmpty)
        }
    }

    @Test
    func isIdempotent() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source)

            #expect(try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination) == .relocated)
            #expect(try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination) == .destinationAlreadyPopulated)
        }
    }

    @Test
    func aFreshInstallIsANoOp() throws {
        try withTemporaryDirectory { root in
            let outcome = try StoreRelocation.relocate(
                storeNamed: Self.storeName,
                from: root.appendingPathComponent("Legacy"),
                to: root.appendingPathComponent("New/Scheduler")
            )
            #expect(outcome == .nothingToRelocate)
        }
    }

    /// Downgrade-then-upgrade: 0.1.x recreated a store at the old path while the new one already holds data.
    @Test
    func anExistingDestinationWins() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source, contents: "stale")
            try makeStore(in: destination, contents: "current")

            let outcome = try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)

            #expect(outcome == .destinationAlreadyPopulated)
            let survivor = try String(contentsOf: destination.appendingPathComponent(Self.storeName), encoding: .utf8)
            #expect(survivor.hasPrefix("current"))
            #expect(storeIsComplete(in: source))
        }
    }

    /// A lone sidecar at the destination must not read as "already migrated" — that would strand the store.
    @Test
    func anOrphanSidecarAtTheDestinationDoesNotBlockRelocation() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try "orphan".write(to: destination.appendingPathComponent("store.sqlite-wal"), atomically: true, encoding: .utf8)

            #expect(try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination) == .relocated)
            #expect(storeIsComplete(in: destination))
        }
    }

    @Test
    func renamingCarriesSidecarsAndTheSupportDirectory() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Documents/GroveScheduler")
            let destination = root.appendingPathComponent("Application Support/app/Scheduler")
            let legacyName = "edu.stanford.spezi.scheduler.storage.sqlite"
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                try "x".write(to: source.appendingPathComponent(legacyName + suffix), atomically: true, encoding: .utf8)
            }
            try FileManager.default.createDirectory(
                at: source.appendingPathComponent(".\(legacyName)_SUPPORT"),
                withIntermediateDirectories: true
            )

            try StoreRelocation.relocate(
                storeNamed: legacyName,
                from: source,
                to: destination,
                renamedTo: "store.sqlite"
            )

            #expect(storeIsComplete(in: destination))
            #expect(try StoreRelocation.storeFiles(named: legacyName, in: source).isEmpty)
        }
    }

    /// The scheduler's iOS 26 marker sits beside the store and decides whether a one-shot database
    /// migration re-runs. Leaving it behind crash-loops the app; inventing one skips a needed migration.
    @Test
    func companionsTravelWhenPresentAndAreNotInvented() throws {
        try withTemporaryDirectory { root in
            let marker = "didPerformIOS26Migration"

            let withMarker = root.appendingPathComponent("a")
            let withMarkerDestination = root.appendingPathComponent("a-new/Scheduler")
            try makeStore(in: withMarker)
            try "".write(to: withMarker.appendingPathComponent(marker), atomically: true, encoding: .utf8)
            try StoreRelocation.relocate(
                storeNamed: Self.storeName, from: withMarker, to: withMarkerDestination, alongside: [marker]
            )
            #expect(FileManager.default.fileExists(atPath: withMarkerDestination.appendingPathComponent(marker).path))
            #expect(!FileManager.default.fileExists(atPath: withMarker.appendingPathComponent(marker).path))

            let withoutMarker = root.appendingPathComponent("b")
            let withoutMarkerDestination = root.appendingPathComponent("b-new/Scheduler")
            try makeStore(in: withoutMarker)
            try StoreRelocation.relocate(
                storeNamed: Self.storeName, from: withoutMarker, to: withoutMarkerDestination, alongside: [marker]
            )
            #expect(!FileManager.default.fileExists(atPath: withoutMarkerDestination.appendingPathComponent(marker).path))
        }
    }

    // MARK: Directories

    @Test
    func relocatesAWholeDirectory() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Documents/Bundles")
            let destination = root.appendingPathComponent("Support/app/Study/Bundles")
            try FileManager.default.createDirectory(at: source.appendingPathComponent("child"), withIntermediateDirectories: true)

            #expect(try StoreRelocation.relocateDirectory(from: source, to: destination) == .relocated)
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("child").path))
            #expect(!FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test
    func anExistingDestinationDirectoryWins() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("old")
            let destination = root.appendingPathComponent("new")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            #expect(try StoreRelocation.relocateDirectory(from: source, to: destination) == .destinationAlreadyPopulated)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test
    func renamesChildrenLongestPrefixFirst() throws {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["a.b.one", "a.two", "unrelated"] {
                try name.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            var matched: [String] = []

            try StoreRelocation.renameChildren(
                matching: [(legacy: "a", current: "A"), (legacy: "a.b", current: "AB")],
                in: root
            ) { matched.append($0) }

            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
            #expect(contents == ["A.two", "AB.one", "unrelated"])
            #expect(matched.sorted() == ["a", "a.b"])
        }
    }

    /// A rename that differs only in case is a real rename on a case-sensitive volume and a no-op move
    /// on a case-insensitive one. Neither may be mistaken for a collision and skipped.
    @Test
    func renamesChildrenDifferingOnlyInCase() throws {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try "payload".write(to: root.appendingPathComponent("lower.x"), atomically: true, encoding: .utf8)

            try StoreRelocation.renameChildren(matching: [(legacy: "lower", current: "Lower")], in: root)

            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(contents == ["Lower.x"])
            #expect(try String(contentsOf: root.appendingPathComponent("Lower.x"), encoding: .utf8) == "payload")
        }
    }

    @Test
    func renamingChildrenNeverOverwrites() throws {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try "old".write(to: root.appendingPathComponent("old.x"), atomically: true, encoding: .utf8)
            try "new".write(to: root.appendingPathComponent("new.x"), atomically: true, encoding: .utf8)

            try StoreRelocation.renameChildren(matching: [(legacy: "old", current: "new")], in: root)

            #expect(try String(contentsOf: root.appendingPathComponent("new.x"), encoding: .utf8) == "new")
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("old.x").path))
        }
    }

    /// An unrelated file that merely starts with the store's name must not be swept up — nor may a
    /// same-named store already living at the destination be deleted by the orphan sweep.
    @Test
    func onlyTheStoresOwnFilesAreTouched() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source)
            try "backup".write(to: source.appendingPathComponent("store.sqlite.backup"), atomically: true, encoding: .utf8)
            try "unrelated".write(to: source.appendingPathComponent("store.sqlite2"), atomically: true, encoding: .utf8)

            try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)

            #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("store.sqlite.backup").path))
            #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("store.sqlite2").path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("store.sqlite.backup").path))
        }
    }

    /// Reporting `.relocated` without a database at the destination would make the caller create an
    /// empty store on top of it, and every later launch would then short-circuit as already migrated.
    @Test
    func anUnreadableSourceThrowsRatherThanReportingSuccess() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: source.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path) }

            #expect(throws: (any Error).self) {
                try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)
            }
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(Self.storeName).path))
        }
    }

    /// A staging directory left by an interrupted attempt is uncommitted by definition, and must not
    /// accumulate a full copy of the store on every failure.
    @Test
    func staleStagingDirectoriesAreSweptBeforeRetrying() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let parent = root.appendingPathComponent("New")
            let destination = parent.appendingPathComponent("Scheduler")
            try makeStore(in: source)
            let stale = parent.appendingPathComponent(".Scheduler.staging-abandoned")
            try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

            try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)

            let leftovers = try FileManager.default.contentsOfDirectory(atPath: parent.path)
                .filter { $0.hasPrefix(".Scheduler.staging-") }
            #expect(leftovers.isEmpty)
            #expect(storeIsComplete(in: destination))
        }
    }

    // MARK: Crash safety

    /// The invariant that matters: however far the relocation got before dying, a complete store is
    /// readable at exactly one location on the next launch, and retrying finishes the job.
    @Test(arguments: 0..<8, [false, true])
    func aCompleteStoreSurvivesFailureAtEveryStep(failAfter operations: Int, destinationExists: Bool) throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Legacy")
            let destination = root.appendingPathComponent("New/Scheduler")
            try makeStore(in: source)
            if destinationExists {
                // Exercises the swap branch, which cannot commit with a single rename.
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try "orphan".write(to: destination.appendingPathComponent("store.sqlite-wal"), atomically: true, encoding: .utf8)
            }

            let interrupted = FailingFileManager(failingAfter: operations)
            let died: Bool
            do {
                _ = try StoreRelocation.relocate(
                    storeNamed: Self.storeName,
                    from: source,
                    to: destination,
                    fileManager: interrupted
                )
                died = false
            } catch {
                died = true
            }

            // A complete store must still exist somewhere. Both locations holding one is fine — that is
            // the window between committing the destination and cleaning up the source, and the
            // destination wins on the next call.
            let atSource = storeIsComplete(in: source)
            let atDestination = storeIsComplete(in: destination)
            #expect(
                atSource || atDestination,
                "after failing at step \(operations): no complete store at either location"
            )

            if died {
                // Whatever was left behind must not stop the next launch from completing the move.
                _ = try StoreRelocation.relocate(storeNamed: Self.storeName, from: source, to: destination)
            }
            #expect(storeIsComplete(in: destination), "retry after failing at step \(operations) did not converge")
        }
    }
}
