//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers


/// Tracks the state of the account startup requirements check, including migration from pre-Grove `@SceneStorage`.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AccountStartupCheckState: Equatable {
    var verifiedAccount: Bool
    var verifiedAccountId: String?
    var legacyVerifiedAccount: Bool?


    init(
        verifiedAccount: Bool = false,
        verifiedAccountId: String? = nil,
        legacyVerifiedAccount: Bool? = nil
    ) {
        self.verifiedAccount = verifiedAccount
        self.verifiedAccountId = verifiedAccountId
        self.legacyVerifiedAccount = legacyVerifiedAccount
    }


    /// Evaluates the startup account check and performs any necessary legacy migration.
    ///
    /// - Parameters:
    ///   - details: Current account details.
    ///   - missingKeys: Missing required keys for the current account configuration.
    /// - Returns: Missing keys that require a follow-up sheet presentation, or `nil` if already verified or migrated.
    mutating func evaluate(
        for details: AccountDetails,
        missingKeys: [any AccountKey.Type]
    ) -> [any AccountKey.Type]? {
        // Handle migration from pre-Grove Spezi scene storage:
        if legacyVerifiedAccount == true {
            LegacyIdentifierReport.encountered(
                LegacySceneStorageKey.accountStartupCheck,
                in: "GroveAccount",
                .duringMigration
            )
            verifiedAccount = true
            verifiedAccountId = details.accountId
            legacyVerifiedAccount = nil
            return nil
        } else if legacyVerifiedAccount != nil {
            legacyVerifiedAccount = nil
        }

        // Avoid allowing stale state from another account to suppress a required follow-up:
        let isAlreadyVerified = verifiedAccount && verifiedAccountId == details.accountId
        guard !isAlreadyVerified else {
            return nil
        }

        verifiedAccount = true
        verifiedAccountId = details.accountId

        if !missingKeys.isEmpty {
            return missingKeys
        }
        return nil
    }

    /// Handles the 5-second initial startup timeout when no account details have completed setup.
    mutating func handleStartupTimeout() {
        verifiedAccount = true
        if legacyVerifiedAccount != nil {
            legacyVerifiedAccount = nil
        }
    }
}
