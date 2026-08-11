//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveDevices
import GroveFoundation
import GroveLegacyIdentifiers
import Testing


@Suite
struct DevicesStorageTests {
    private let fileManager = FileManager.default

    private func withDirectories(_ body: (_ namespace: StorageNamespace, _ legacyRoot: URL, _ root: URL) throws -> Void) rethrows {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let legacyRoot = root.appendingPathComponent("Documents")
        try? fileManager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try body(.custom("edu.stanford.SpeziDevices.unitTests.\(UUID().uuidString)"), legacyRoot, root)
    }

    private func writeStore(named name: String, in directory: URL, contents: String) throws {
        for suffix in ["", "-wal", "-shm"] {
            try "\(contents)\(suffix)".write(
                to: directory.appendingPathComponent(name + suffix),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    @Test
    func relocatesTheLooseDocumentsStore() throws {
        try withDirectories { namespace, legacyRoot, _ in
            defer { try? fileManager.removeItem(at: try namespace.containerURL()) }
            try writeStore(named: LegacyStorage.pairedDevicesStore, in: legacyRoot, contents: "paired")

            let store = try #require(DevicesStorage.prepareStore(
                .pairedDevices,
                migratingFrom: LegacyStorage.pairedDevicesStore,
                in: namespace,
                legacyRoot: legacyRoot
            ))

            #expect(try String(contentsOf: store, encoding: .utf8) == "paired")
            #expect(store.lastPathComponent == "store.sqlite")
            #expect(store.deletingLastPathComponent().lastPathComponent == "PairedDevices")
            #expect(fileManager.fileExists(atPath: store.deletingLastPathComponent().appendingPathComponent("store.sqlite-wal").path))
            #expect(!fileManager.fileExists(atPath: legacyRoot.appendingPathComponent(LegacyStorage.pairedDevicesStore).path))
        }
    }

    /// Each store gets its own component directory, so neither relocation has to copy into a
    /// directory the other already created.
    @Test
    func theTwoStoresDoNotShareADirectory() throws {
        try withDirectories { namespace, legacyRoot, _ in
            defer { try? fileManager.removeItem(at: try namespace.containerURL()) }
            try writeStore(named: LegacyStorage.pairedDevicesStore, in: legacyRoot, contents: "paired")
            try writeStore(named: LegacyStorage.healthMeasurementsStore, in: legacyRoot, contents: "measurements")

            let paired = try #require(DevicesStorage.prepareStore(
                .pairedDevices, migratingFrom: LegacyStorage.pairedDevicesStore, in: namespace, legacyRoot: legacyRoot
            ))
            let measurements = try #require(DevicesStorage.prepareStore(
                .healthMeasurements, migratingFrom: LegacyStorage.healthMeasurementsStore, in: namespace, legacyRoot: legacyRoot
            ))

            #expect(paired.deletingLastPathComponent() != measurements.deletingLastPathComponent())
            #expect(try String(contentsOf: paired, encoding: .utf8) == "paired")
            #expect(try String(contentsOf: measurements, encoding: .utf8) == "measurements")
        }
    }

    @Test
    func aFreshInstallGetsAnEmptyDirectory() throws {
        try withDirectories { namespace, legacyRoot, _ in
            defer { try? fileManager.removeItem(at: try namespace.containerURL()) }

            let store = try #require(DevicesStorage.prepareStore(
                .pairedDevices, migratingFrom: LegacyStorage.pairedDevicesStore, in: namespace, legacyRoot: legacyRoot
            ))

            #expect(fileManager.fileExists(atPath: store.deletingLastPathComponent().path))
            #expect(!fileManager.fileExists(atPath: store.path))
        }
    }

    @Test
    func isIdempotent() throws {
        try withDirectories { namespace, legacyRoot, _ in
            defer { try? fileManager.removeItem(at: try namespace.containerURL()) }
            try writeStore(named: LegacyStorage.pairedDevicesStore, in: legacyRoot, contents: "paired")

            let first = DevicesStorage.prepareStore(
                .pairedDevices, migratingFrom: LegacyStorage.pairedDevicesStore, in: namespace, legacyRoot: legacyRoot
            )
            let second = DevicesStorage.prepareStore(
                .pairedDevices, migratingFrom: LegacyStorage.pairedDevicesStore, in: namespace, legacyRoot: legacyRoot
            )

            #expect(first == second)
            #expect(try String(contentsOf: try #require(second), encoding: .utf8) == "paired")
        }
    }

    // MARK: Preferences

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "edu.stanford.SpeziDevices.unitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test
    func migratesPreferenceKeys() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: LegacyPreferenceKey.devicesEverPairedOnce)
            defaults.set("complete", forKey: LegacyPreferenceKey.devicesAccessorySetupKitMigration)

            DevicesStorage.migratePreferences(in: defaults)

            #expect(defaults.bool(forKey: DevicesStorage.everPairedOnceKey))
            #expect(defaults.string(forKey: DevicesStorage.accessorySetupKitMigrationKey) == "complete")
            #expect(defaults.object(forKey: LegacyPreferenceKey.devicesEverPairedOnce) == nil)
            #expect(defaults.object(forKey: LegacyPreferenceKey.devicesAccessorySetupKitMigration) == nil)
        }
    }

    /// Losing the AccessorySetupKit flag re-prompts the user to pair accessories they already paired,
    /// so a value already present at the new key must never be clobbered by a stale legacy one.
    @Test
    func doesNotOverwriteAnAlreadyMigratedValue() throws {
        try withDefaults { defaults in
            defaults.set("complete", forKey: DevicesStorage.accessorySetupKitMigrationKey)
            defaults.set("notDetermined", forKey: LegacyPreferenceKey.devicesAccessorySetupKitMigration)

            DevicesStorage.migratePreferences(in: defaults)

            #expect(defaults.string(forKey: DevicesStorage.accessorySetupKitMigrationKey) == "complete")
        }
    }

    @Test
    func migratingPreferencesIsIdempotentAndSafeWhenEmpty() throws {
        try withDefaults { defaults in
            DevicesStorage.migratePreferences(in: defaults)
            DevicesStorage.migratePreferences(in: defaults)

            #expect(defaults.object(forKey: DevicesStorage.everPairedOnceKey) == nil)
        }
    }
}
