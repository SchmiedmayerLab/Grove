//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Foundation
import GroveFoundation
import GroveLegacyIdentifiers
@testable import GroveStudy
import Testing


/// Throws on every copy, which fails a relocation after the legacy data has been found — the exact
/// state the fallback paths exist for.
private final class CopyFailingFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }

    // A whole-directory relocation commits by move rather than copy, so both must fail for the
    // "relocation failed" state these tests exercise.
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}


/// The failure paths matter more than the happy ones here: `StudyManager.configure()` deletes
/// unmatched children of the bundles directory, so a preparation step that reports the wrong thing
/// after an IO failure turns a transient error into deleted study content.
@Suite
struct StudyStorageTests {
    private let fileManager = FileManager.default

    private func makeLegacyRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func relocatesTheStoreOnFirstLaunch() throws {
        let legacyRoot = try makeLegacyRoot()
        defer { try? fileManager.removeItem(at: legacyRoot) }
        try "rows".write(
            to: legacyRoot.appendingPathComponent(LegacyStorage.studyStore),
            atomically: true,
            encoding: .utf8
        )
        let namespace = StorageNamespace.custom("study-tests-\(UUID().uuidString)")

        let store = StudyStorage.prepareStore(in: namespace, legacyRoot: legacyRoot)

        let url = try #require(store)
        #expect(try String(contentsOf: url, encoding: .utf8) == "rows")
        #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent(LegacyStorage.studyStore).path))
    }

    /// A failed relocation must hand back the legacy store, not the empty destination: a fresh
    /// `ModelContainer` at the destination would permanently mask the stranded data.
    @Test
    func aFailedRelocationKeepsUsingTheLegacyStore() throws {
        let legacyRoot = try makeLegacyRoot()
        defer { try? fileManager.removeItem(at: legacyRoot) }
        let legacyStore = legacyRoot.appendingPathComponent(LegacyStorage.studyStore)
        try "rows".write(to: legacyStore, atomically: true, encoding: .utf8)
        let namespace = StorageNamespace.custom("study-tests-\(UUID().uuidString)")

        let store = StudyStorage.prepareStore(
            in: namespace,
            legacyRoot: legacyRoot,
            fileManager: CopyFailingFileManager()
        )

        #expect(store == legacyStore)
        #expect(fileManager.fileExists(atPath: legacyStore.path))
        // And the retry succeeds once the failure clears.
        let retried = StudyStorage.prepareStore(in: namespace, legacyRoot: legacyRoot)
        let url = try #require(retried)
        #expect(url != legacyStore)
        #expect(try String(contentsOf: url, encoding: .utf8) == "rows")
    }

    /// A failed bundles relocation must not create the destination: an existing destination makes
    /// the next launch's relocation conclude it already ran and never retry.
    @Test
    func aFailedBundlesRelocationReportsFailureAndCreatesNothing() throws {
        let legacyRoot = try makeLegacyRoot()
        defer { try? fileManager.removeItem(at: legacyRoot) }
        let legacyBundles = legacyRoot.appendingPathComponent(LegacyStorage.studyBundlesDirectory, isDirectory: true)
        try fileManager.createDirectory(at: legacyBundles, withIntermediateDirectories: true)
        try "definition".write(
            to: legacyBundles.appendingPathComponent("a.\(LegacyStorage.studyBundleFileExtension)"),
            atomically: true,
            encoding: .utf8
        )
        let namespace = StorageNamespace.custom("study-tests-\(UUID().uuidString)")

        let directory = StudyStorage.prepareBundlesDirectory(
            in: namespace,
            legacyRoot: legacyRoot,
            fileManager: CopyFailingFileManager()
        )

        #expect(directory == nil)
        #expect(fileManager.fileExists(atPath: legacyBundles.path))
        // The retry brings the bundle forward and renames its extension in the same pass.
        let retried = StudyStorage.prepareBundlesDirectory(in: namespace, legacyRoot: legacyRoot)
        let url = try #require(retried)
        let children = try fileManager.contentsOfDirectory(atPath: url.path)
        #expect(children == ["a.\(StudyBundle.fileExtension)"])
    }

    @Test
    func renamesLegacyBundleExtensions() throws {
        let legacyRoot = try makeLegacyRoot()
        defer { try? fileManager.removeItem(at: legacyRoot) }
        let legacyBundles = legacyRoot.appendingPathComponent(LegacyStorage.studyBundlesDirectory, isDirectory: true)
        try fileManager.createDirectory(at: legacyBundles, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try "definition".write(
            to: legacyBundles.appendingPathComponent("\(id).\(LegacyStorage.studyBundleFileExtension)"),
            atomically: true,
            encoding: .utf8
        )
        let namespace = StorageNamespace.custom("study-tests-\(UUID().uuidString)")

        let directory = StudyStorage.prepareBundlesDirectory(in: namespace, legacyRoot: legacyRoot)

        let url = try #require(directory)
        #expect(fileManager.fileExists(atPath: url.appendingPathComponent("\(id).\(StudyBundle.fileExtension)").path))
        #expect(!fileManager.fileExists(atPath: url.appendingPathComponent("\(id).\(LegacyStorage.studyBundleFileExtension)").path))
    }
}
#endif
