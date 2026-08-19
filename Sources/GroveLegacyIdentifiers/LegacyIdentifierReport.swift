//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(os)
import os
#endif

/// Reports that a pre-Grove identifier turned up at runtime.
///
/// Whether that is news depends entirely on where it happened, so the caller says so rather than
/// this type guessing:
///
/// - Migrating on first launch after an update — expected, exactly once. A notice.
/// - The same legacy path on a later launch — the migration regressed. An error, and a trap in debug
///   builds, because it means data is being read from somewhere nothing writes to any more.
/// - A superseded URL in a third-party FHIR resource — permanently expected, and not reported at all.
///   Those go through the supersession mechanism, never through here.
public enum LegacyIdentifierReport {
    /// How to treat an encounter with a legacy identifier.
    public enum Expectation: Sendable {
        /// A migration is running now. Logged, never fatal.
        case duringMigration
        /// Nothing should still be reading this. Logged as an error, and traps in debug builds.
        case afterMigration
    }

    #if canImport(os)
    private static let logger = Logger(subsystem: "org.grovealliance.legacyIdentifiers", category: "Migration")
    #endif

    /// Records an encounter with a legacy identifier.
    ///
    /// - Parameters:
    ///   - identifier: The pre-Grove identifier that was found.
    ///   - subsystem: The module that found it, for the log.
    ///   - expectation: Whether finding it here is normal.
    ///   - remedy: What the developer should do, when there is something they can do.
    public static func encountered(
        _ identifier: String,
        in subsystem: String,
        _ expectation: Expectation,
        remedy: String? = nil
    ) {
        let suffix = remedy.map { " \($0)" } ?? ""
        switch expectation {
        case .duringMigration:
            log(notice: "\(subsystem): migrating data stored under the legacy identifier '\(identifier)'.\(suffix)")
        case .afterMigration:
            let message = """
                \(subsystem): found the legacy identifier '\(identifier)' after its migration should \
                have completed. Data written under it is not being read.\(suffix)
                """
            log(error: message)
            assertionFailure(message)
        }
    }

    private static func log(notice message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    private static func log(error message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}
