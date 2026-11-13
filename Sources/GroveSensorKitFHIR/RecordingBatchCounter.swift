//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SQLite


/// Counts exact distinct batches without retaining every device/identifier pair in memory.
/// The existing SQLite dependency supplies a private temporary database, removed when closed.
final class RecordingBatchCounter {
    /// Storage failures must propagate without being classified as malformed clinical input.
    enum Failure: Error { case indexUnavailable }

    private let database: Connection
    private let insert: Statement
    private(set) var count = 0

    init() throws {
        do {
            let database = try Connection(.temporary)
            // This disposable index owns no authoritative state. SQLite's spill threshold is
            // independent of cache_size and can default much higher; configure both explicitly.
            try database.execute("""
                PRAGMA temp_store = FILE;
                PRAGMA journal_mode = OFF;
                PRAGMA cache_size = -1024;
                PRAGMA cache_spill = 256;
                CREATE TABLE batches (device BLOB NOT NULL, identifier BLOB NOT NULL, PRIMARY KEY (device, identifier)) WITHOUT ROWID;
                BEGIN;
                """)
            self.database = database
            self.insert = try database.prepare("INSERT OR IGNORE INTO batches (device, identifier) VALUES (?, ?)")
        } catch {
            throw Failure.indexUnavailable
        }
    }

    func add(device: String, identifier: String) throws {
        do {
            // Swift String equality treats canonical Unicode equivalents as equal. Preserve that
            // behavior in the disk index, without changing the original recording bytes. Blobs also
            // preserve embedded NULs, which SQLite.swift's C-string binding would truncate.
            try insert.run(
                Blob(bytes: Array(device.precomposedStringWithCanonicalMapping.utf8)),
                Blob(bytes: Array(identifier.precomposedStringWithCanonicalMapping.utf8))
            )
            count += database.changes
        } catch {
            throw Failure.indexUnavailable
        }
    }
}
