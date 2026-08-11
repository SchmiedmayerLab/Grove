//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers
@testable import GroveLocalStorage
import Testing


/// The highest-blast-radius migration in the release: this directory holds every value `LocalStorage`
/// has ever written, including the HealthKit anchors whose loss makes an app re-import a user's
/// entire health history.
@Suite
struct LocalStorageMigrationTests {
    private let fileManager = FileManager.default

    private func withDirectories(_ body: (_ current: URL, _ legacy: URL) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        try body(
            root.appendingPathComponent("Application Support/app/LocalStorage"),
            root.appendingPathComponent("Application Support/edu.stanford.spezi/LocalStorage")
        )
    }

    private func write(_ name: String, in directory: URL, contents: String = "value") throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func contents(of directory: URL) -> Set<String> {
        Set((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    @Test
    func relocatesTheWholeDirectory() throws {
        try withDirectories { current, legacy in
            try write("some.key.localstorage", in: legacy)

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == ["some.key.localstorage"])
            #expect(!fileManager.fileExists(atPath: legacy.path))
        }
    }

    @Test
    func renamesEveryLegacyKeyPrefix() throws {
        try withDirectories { current, legacy in
            let anchors = "\(LegacyStorageKeyPrefix.healthKitQueryAnchors).HKQuantityTypeIdentifierStepCount.localstorage"
            let starts = "\(LegacyStorageKeyPrefix.healthKitSampleCollectionStartDates).HKQuantityTypeIdentifierHeartRate.localstorage"
            let sensor = "\(LegacyStorageKeyPrefix.sensorKitQueryAnchors).ambientLight.localstorage"
            let export = "\(LegacyStorageKeyPrefix.bulkExportSessions).ABC123.localstorage"
            let account = "\(LegacyStorageKeyPrefix.accountDetailsCache).user-1.localstorage"
            for name in [anchors, starts, sensor, export, account] {
                try write(name, in: legacy, contents: name)
            }

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == [
                "HealthKit.queryAnchors.HKQuantityTypeIdentifierStepCount.localstorage",
                "HealthKit.sampleCollectionStartDates.HKQuantityTypeIdentifierHeartRate.localstorage",
                "SensorKit.queryAnchors.ambientLight.localstorage",
                "HealthKit.bulkExport.ABC123.localstorage",
                "Account.detailsCache.user-1.localstorage"
            ])
        }
    }

    /// `…queryAnchors` is a prefix of nothing else, but `…sampleCollectionStartDates` and
    /// `…queryAnchors` share a long common stem. Renaming must match the longest prefix first.
    @Test
    func aLongerPrefixIsNotShadowedByAShorterOne() throws {
        try withDirectories { current, legacy in
            let starts = "\(LegacyStorageKeyPrefix.healthKitSampleCollectionStartDates).x.localstorage"
            try write(starts, in: legacy)

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == ["HealthKit.sampleCollectionStartDates.x.localstorage"])
        }
    }

    @Test
    func contentIsMovedVerbatimAndNeverDecoded() throws {
        try withDirectories { current, legacy in
            let name = "\(LegacyStorageKeyPrefix.healthKitQueryAnchors).x.localstorage"
            try write(name, in: legacy, contents: "encrypted-bytes")

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            let moved = current.appendingPathComponent("HealthKit.queryAnchors.x.localstorage")
            #expect(try String(contentsOf: moved, encoding: .utf8) == "encrypted-bytes")
        }
    }

    @Test
    func unrelatedEntriesAreLeftAlone() throws {
        try withDirectories { current, legacy in
            try write("org.example.app.someKey.localstorage", in: legacy)

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == ["org.example.app.someKey.localstorage"])
        }
    }

    /// Downgrade-then-upgrade: an older release recreated the legacy directory while the current one
    /// already holds the real data. Adopting the legacy one would roll the user back.
    @Test
    func anExistingCurrentDirectoryWins() throws {
        try withDirectories { current, legacy in
            try write("current.localstorage", in: current, contents: "authoritative")
            try write("stale.localstorage", in: legacy, contents: "stale")

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == ["current.localstorage"])
            #expect(fileManager.fileExists(atPath: legacy.path))
        }
    }

    /// A rename must never clobber an entry already written under the new name.
    @Test
    func anAlreadyRenamedEntryIsNotOverwritten() throws {
        try withDirectories { current, legacy in
            try write("\(LegacyStorageKeyPrefix.healthKitQueryAnchors).x.localstorage", in: legacy, contents: "old")
            try write("HealthKit.queryAnchors.x.localstorage", in: legacy, contents: "new")

            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            let survivor = current.appendingPathComponent("HealthKit.queryAnchors.x.localstorage")
            #expect(try String(contentsOf: survivor, encoding: .utf8) == "new")
        }
    }

    @Test
    func isIdempotent() throws {
        try withDirectories { current, legacy in
            try write("\(LegacyStorageKeyPrefix.healthKitQueryAnchors).x.localstorage", in: legacy)

            LocalStorage.migrateIfNeeded(into: current, from: legacy)
            let afterFirst = contents(of: current)
            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(contents(of: current) == afterFirst)
        }
    }

    /// The modules that read these prefixes must use exactly what the migration renames to. A drift
    /// between the two is silent: the files move, and then nothing looks for them at the new name.
    @Test
    func everyRenameTargetIsBrandFreeAndUnique() {
        let targets = LocalStorage.legacyKeyPrefixRenames.map(\.current)

        #expect(Set(targets).count == targets.count)
        for target in targets {
            for token in ["spezi", "grove", "stanford", "edu.", "cardinalkit"] {
                #expect(!target.lowercased().contains(token), "'\(token)' must not appear in '\(target)'")
            }
        }
    }

    /// Longest-first ordering is what stops `…queryAnchors` shadowing
    /// `…sampleCollectionStartDates`; assert the inputs really do need it.
    @Test
    func prefixesThatShareAStemAreAllDistinct() {
        let legacy = LocalStorage.legacyKeyPrefixRenames.map(\.legacy)
        #expect(Set(legacy).count == legacy.count)
    }

    @Test
    func aFreshInstallIsANoOp() {
        withDirectories { current, legacy in
            LocalStorage.migrateIfNeeded(into: current, from: legacy)

            #expect(!fileManager.fileExists(atPath: current.path))
        }
    }
}
