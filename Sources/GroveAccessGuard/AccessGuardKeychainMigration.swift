//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveKeychainStorage
import GroveLegacyIdentifiers
import OSLog


private let logger = Logger(subsystem: "org.grovealliance.accessGuard", category: "Migration")


/// Moves stored passcodes onto the current keychain service.
///
/// The riskiest migration in the module: a passcode that does not come across leaves the user locked
/// out of their own app with no recovery path. Three properties follow from that.
///
/// **Every account moves, not just the configured ones.** Biometric fallback passcodes are stored
/// under identifiers that never appear in `AccessGuards.configs`, so iterating the configuration
/// would silently leave them behind. The whole service is enumerated instead.
///
/// **A locked keychain defers rather than completing.** Before first unlock — a background launch
/// after reboot — the keychain returns nothing, which is indistinguishable from "no passcodes" unless
/// the error is inspected. Concluding "nothing to migrate" there would let the app decide the user
/// has no passcode and offer to set a new one, sweeping the original.
///
/// **Nothing is deleted until everything is written.** A partial copy followed by a delete would lose
/// exactly the accounts that failed.
@available(iOS 18, macOS 15, watchOS 11, *)
enum AccessGuardKeychainMigration {
    /// Brings every stored passcode onto the current service.
    ///
    /// - Parameter keychain: The keychain to migrate within.
    /// - Returns: Whether the module may now read from the current service. `false` means the
    ///     keychain was unavailable and the caller must not treat an empty result as "no passcode".
    @discardableResult
    static func run(in keychain: KeychainStorage) -> Bool {
        let legacy = CredentialsTag.legacyAccessGuard
        let current = CredentialsTag.accessGuard

        let existing: [Credentials]
        do {
            existing = try keychain.retrieveAllCredentials(withUsername: nil, for: legacy)
        } catch {
            // Cannot distinguish "empty" from "locked", so assume the worst and retry next launch.
            logger.error("Could not read the legacy access guard service; deferring migration: \(error)")
            return false
        }
        guard !existing.isEmpty else {
            return true
        }

        LegacyIdentifierReport.encountered(LegacyKeychain.accessGuardService, in: "GroveAccessGuard", .duringMigration)

        for credentials in existing {
            do {
                try keychain.store(Credentials(username: credentials.username, password: credentials.password), for: current)
            } catch {
                // Leave the legacy items in place; a half-migrated set is recoverable, a deleted one
                // is not.
                logger.error("Could not copy an access guard passcode; leaving the legacy items: \(error)")
                return false
            }
        }

        for credentials in existing {
            do {
                try keychain.deleteCredentials(withUsername: credentials.username, for: legacy)
            } catch {
                // The current service is authoritative now, so a leftover legacy item is harmless.
                logger.warning("Could not remove a migrated access guard passcode: \(error)")
            }
        }
        return true
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension CredentialsTag {
    /// The service passcodes were stored under before the rename.
    static var legacyAccessGuard: Self {
        .genericPassword(forService: LegacyKeychain.accessGuardService)
    }
}
