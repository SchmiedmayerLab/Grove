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


private let logger = Logger(subsystem: "org.grovealliance.localStorage", category: "Migration")


extension StorageNamespace.Component {
    /// Where `LocalStorage` keeps its entries.
    static let localStorage = Self("LocalStorage")
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalStorage {
    /// The directory `LocalStorage` used before the rename.
    static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(LegacyStorage.localStorageDirectory)
    }

    /// Key prefixes that changed with the rename.
    static var legacyKeyPrefixRenames: [(legacy: String, current: String)] {
        [
            (LegacyStorageKeyPrefix.healthKitSampleCollectionStartDates, "HealthKit.sampleCollectionStartDates"),
            (LegacyStorageKeyPrefix.healthKitQueryAnchors, "HealthKit.queryAnchors"),
            (LegacyStorageKeyPrefix.sensorKitQueryAnchors, "SensorKit.queryAnchors"),
            (LegacyStorageKeyPrefix.bulkExportSessions, "HealthKit.bulkExport"),
            (LegacyStorageKeyPrefix.accountDetailsCache, "Account.detailsCache")
        ]
    }
    /// Brings `LocalStorage` forward from the layout used before the rename.
    ///
    /// Two steps, in order. The directory move must come first: the key renames operate on the files
    /// inside it, and running them against the old location would migrate data that is then left
    /// behind.
    ///
    /// Every entry ever written by `LocalStorage` lives here — HealthKit and SensorKit query anchors,
    /// bulk-export session state, cached account details. Losing the anchors makes an app re-import
    /// the user's entire HealthKit history and duplicate it in the study database, so this migration
    /// never deletes and never overwrites.
    ///
    /// - Parameters:
    ///   - directory: The directory `LocalStorage` uses now.
    ///   - legacyDirectory: The directory it used before.
    /// - Returns: `false` if the migration could not complete, in which case the caller must not
    ///     create the destination — an empty directory there makes every later launch conclude the
    ///     migration already ran and strands every stored value.
    @discardableResult
    static func migrateIfNeeded(into directory: URL, from legacyDirectory: URL, fileManager: FileManager = .default) -> Bool {
        guard relocateDirectory(into: directory, from: legacyDirectory, fileManager: fileManager) else {
            return false
        }
        renameLegacyKeyPrefixes(in: directory, fileManager: fileManager)
        return true
    }

    /// Moves the whole legacy directory across in one atomic rename.
    private static func relocateDirectory(into directory: URL, from legacyDirectory: URL, fileManager: FileManager) -> Bool {
        do {
            let outcome = try StoreRelocation.relocateDirectory(
                from: legacyDirectory,
                to: directory,
                fileManager: fileManager
            )
            if outcome == .relocated {
                LegacyIdentifierReport.encountered(LegacyStorage.localStorageDirectory, in: "GroveLocalStorage")
            }
            return true
        } catch {
            logger.error("Unable to relocate the LocalStorage directory: \(error)")
            return false
        }
    }

    /// Renames entries whose key carried a pre-Grove prefix.
    ///
    /// The keys are not enumerable — anchors are suffixed with a sample type identifier, exports with
    /// a session identifier — so this renames by prefix over the directory's contents rather than key
    /// by key. Entries are moved verbatim: encryption is not bound to the file name, so the bytes are
    /// still readable under the new one and nothing has to be decrypted to migrate it.
    private static func renameLegacyKeyPrefixes(in directory: URL, fileManager: FileManager) {
        do {
            try StoreRelocation.renameChildren(
                matching: Self.legacyKeyPrefixRenames,
                in: directory,
                fileManager: fileManager
            ) { legacyPrefix in
                LegacyIdentifierReport.encountered(legacyPrefix, in: "GroveLocalStorage")
            }
        } catch {
            logger.error("Unable to rename a LocalStorage entry: \(error)")
        }
    }
}
