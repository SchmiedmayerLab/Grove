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
import OSLog


private let logger = Logger(subsystem: "org.grovealliance.scheduler", category: "Storage")


/// The scheduler's store could not be brought forward safely, so nothing was opened.
///
/// Deliberately not a crash: the user's data is still where the previous version left it, and a later
/// launch can retry. Opening a fresh store instead would make that data permanently unreachable.
struct SchedulerStorageUnavailableError: Error, CustomStringConvertible {
    var description: String {
        "The scheduler's persistent store could not be prepared. Existing data was left untouched."
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Scheduler {
    /// The scheduler's database, inside its storage directory.
    nonisolated static let storeFilename = "store.sqlite"

    /// Prepares the scheduler's storage directory, bringing forward a store left by any earlier layout.
    ///
    /// Predecessors are tried newest first, so a device carrying more than one — a 0.1.x install
    /// interrupted part-way through its own migration — adopts the current one:
    ///
    /// 1. the legacy file name inside `directory` itself, which is what a caller who passed an
    ///    explicit `.onDisk(directory:)` has; renamed in place
    /// 2. `Documents/GroveScheduler/edu.stanford.spezi.scheduler.storage.sqlite`
    /// 3. `Documents/edu.stanford.spezi.scheduler.storage.sqlite`, the layout (2) replaced
    ///
    /// The iOS 26 marker travels with the store. Left behind, its migration re-runs against
    /// already-migrated rows and traps on launch; invented, a device that genuinely needs that
    /// migration silently skips it.
    ///
    /// - Parameters:
    ///   - directory: The scheduler's storage directory. Not required to exist.
    ///   - legacyRoot: Where the predecessor layouts lived. Injectable so a test never reads the
    ///     developer's own `~/Documents`.
    /// - Returns: The URL of the store to open, or `nil` if the location could not be made safe to
    ///     use. Never returns a URL whose directory may still be mid-migration.
    @discardableResult
    nonisolated static func prepareStorage(in directory: URL, migratingFrom legacyRoot: URL = .documentsDirectory) -> URL? {
        let store = directory.appendingPathComponent(storeFilename)
        let predecessors = [
            directory,
            legacyRoot.appendingPathComponent(LegacyStorage.schedulerDirectory),
            legacyRoot
        ]

        for source in predecessors {
            do {
                let outcome = try StoreRelocation.relocate(
                    storeNamed: LegacyStorage.schedulerStore,
                    from: source,
                    to: directory,
                    renamedTo: storeFilename,
                    alongside: [didPerformIOS26MigrationFlagFilename]
                )
                if outcome == .relocated {
                    LegacyIdentifierReport.encountered(
                        LegacyStorage.schedulerStore,
                        in: "GroveScheduler"
                    )
                    break
                }
            } catch {
                // A failure here leaves the destination without a database, so returning nil keeps the
                // caller from creating an empty store on top of it — which would make every later
                // launch short-circuit on "destination already populated" and strand the real store.
                // Continuing to an older predecessor could adopt, and then delete, a stale store while
                // the newer one stays unreachable.
                logger.error("Unable to relocate the scheduler store from \(source.path, privacy: .public): \(error)")
                return nil
            }
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Unable to create the scheduler storage directory: \(error)")
            return nil
        }
        return store
    }
}


extension StorageNamespace.Component {
    /// Where the scheduler keeps its store.
    static let scheduler = Self("Scheduler")
}
#endif
