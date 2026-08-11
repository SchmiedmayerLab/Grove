//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import GroveLegacyIdentifiers
import OSLog


/// Resolves the on-disk locations of the stores this module owns, relocating them out of the
/// documents directory on first launch after the update.
///
/// Each store gets its own component directory rather than sharing one, so every relocation can be
/// committed by an atomic directory rename instead of copying into a directory that already exists.
enum DevicesStorage {
    static let storeFilename = "store.sqlite"

    /// Whether any device has ever been paired.
    static let everPairedOnceKey = "Devices.everPairedOnce"
    /// Whether the one-shot AccessorySetupKit migration has run.
    static let accessorySetupKitMigrationKey = "Devices.accessorySetupKitMigration"

    /// Brings the module's `UserDefaults` entries forward onto their un-branded keys.
    ///
    /// Written before the new key so that losing power between the two re-runs the migration rather
    /// than dropping the value — `askit-migration` gates a one-shot pairing migration, and losing it
    /// makes the user re-pair accessories they already paired.
    static func migratePreferences(in defaults: UserDefaults = .standard) {
        let pairs = [
            (LegacyPreferenceKey.devicesEverPairedOnce, everPairedOnceKey),
            (LegacyPreferenceKey.devicesAccessorySetupKitMigration, accessorySetupKitMigrationKey)
        ]
        for (legacy, current) in pairs {
            guard defaults.object(forKey: current) == nil,
                  let value = defaults.object(forKey: legacy) else {
                continue
            }
            defaults.set(value, forKey: current)
            defaults.removeObject(forKey: legacy)
            LegacyIdentifierReport.encountered(legacy, in: "GroveDevices", .duringMigration)
        }
    }

    /// Prepares a store's directory, bringing forward the copy that used to sit loose in `Documents`.
    ///
    /// - Parameters:
    ///   - component: The store's directory within the namespace.
    ///   - legacyStoreName: The file name the store had in the documents directory.
    ///   - namespace: The app's storage namespace.
    ///   - legacyRoot: Where the store used to live. Injectable so tests never touch real `Documents`.
    /// - Returns: The store URL, or `nil` if no usable location could be resolved.
    static func prepareStore(
        _ component: StorageNamespace.Component,
        migratingFrom legacyStoreName: String,
        in namespace: StorageNamespace = .app,
        legacyRoot: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        fileManager: FileManager = .default
    ) -> URL? {
        let directory: URL
        do {
            directory = try namespace.directory(component)
        } catch {
            logger.error("Unable to resolve a storage directory for \(component.name, privacy: .public): \(error)")
            return nil
        }

        do {
            let outcome = try StoreRelocation.relocate(
                storeNamed: legacyStoreName,
                from: legacyRoot,
                to: directory,
                renamedTo: storeFilename,
                fileManager: fileManager
            )
            if outcome == .relocated {
                LegacyIdentifierReport.encountered(legacyStoreName, in: "GroveDevices", .duringMigration)
            }
        } catch {
            // Creating the directory now would let the next launch conclude the migration already
            // ran and strand the real store. But returning nil sends the caller to an in-memory
            // fallback, where new pairings and measurements vanish with the process — so if the
            // legacy store is still on disk, keep using it in place: data accrues where it already
            // lives, and the relocation retries next launch.
            logger.error("Unable to relocate \(legacyStoreName, privacy: .public); continuing against the legacy store: \(error)")
            let legacyStore = legacyRoot.appendingPathComponent(legacyStoreName)
            if fileManager.fileExists(atPath: legacyStore.path) {
                return legacyStore
            }
            return nil
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Unable to create \(directory.path, privacy: .public): \(error)")
            return nil
        }
        return directory.appendingPathComponent(storeFilename)
    }
}


extension StorageNamespace.Component {
    /// Where the paired-device registry keeps its store.
    static let pairedDevices = Self("PairedDevices")
    /// Where recorded health measurements keep their store.
    static let healthMeasurements = Self("HealthMeasurements")
}


private let logger = Logger(subsystem: "org.grovealliance.devices", category: "Storage")
