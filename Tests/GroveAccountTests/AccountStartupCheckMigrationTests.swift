//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveAccount
import GroveLegacyIdentifiers
import Testing


@Suite("Account Startup Check Migration Tests")
struct AccountStartupCheckMigrationTests {
    @Test
    func legacyIdentifierConstantMatchesPreGroveSpelling() {
        #expect(LegacySceneStorageKey.accountStartupCheck == "edu.stanford.spezi-account.startup-account-check")
        #expect(!LegacySceneStorageKey.accountStartupCheck.isEmpty)
    }

    @Test
    func migratesCompletedPreGroveStateForActiveAccount() {
        let accountA = AccountDetails.mock(id: UUID())
        var state = AccountStartupCheckState(
            verifiedAccount: false,
            verifiedAccountId: nil,
            legacyVerifiedAccount: true
        )

        let followUp = state.evaluate(for: accountA, missingKeys: [AccountKeys.name])

        #expect(followUp == nil, "A completed check from pre-Grove build must not re-prompt the user.")
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountA.accountId)
        #expect(state.legacyVerifiedAccount == nil, "Transitional legacy key must be cleared once migrated.")
    }

    @Test
    func doesNotMigrateIncompletePreGroveState() {
        let accountA = AccountDetails.mock(id: UUID())
        var state = AccountStartupCheckState(
            verifiedAccount: false,
            verifiedAccountId: nil,
            legacyVerifiedAccount: false
        )

        let followUp = state.evaluate(for: accountA, missingKeys: [AccountKeys.name])

        #expect(followUp?.count == 1, "An incomplete pre-Grove check must prompt for missing keys.")
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountA.accountId)
        #expect(state.legacyVerifiedAccount == nil, "Legacy false value should be cleared.")
    }

    @Test
    func freshInstallPromptsForMissingKeys() {
        let accountA = AccountDetails.mock(id: UUID())
        var state = AccountStartupCheckState()

        let followUp = state.evaluate(for: accountA, missingKeys: [AccountKeys.name, AccountKeys.genderIdentity])

        #expect(followUp?.count == 2)
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountA.accountId)
        #expect(state.legacyVerifiedAccount == nil)
    }

    @Test
    func alreadyVerifiedAccountIsNotPromptedAgain() {
        let accountA = AccountDetails.mock(id: UUID())
        var state = AccountStartupCheckState(
            verifiedAccount: true,
            verifiedAccountId: accountA.accountId,
            legacyVerifiedAccount: nil
        )

        let followUp = state.evaluate(for: accountA, missingKeys: [AccountKeys.name])

        #expect(followUp == nil, "Already verified account must not be prompted again.")
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountA.accountId)
    }

    @Test
    func accountChangePreventsStaleStateFromSuppressingFollowUp() {
        let accountA = AccountDetails.mock(id: UUID())
        let accountB = AccountDetails.mock(id: UUID())
        #expect(accountA.accountId != accountB.accountId)

        // Account A was verified
        var state = AccountStartupCheckState(
            verifiedAccount: true,
            verifiedAccountId: accountA.accountId,
            legacyVerifiedAccount: nil
        )

        // Account B logs in with missing keys
        let followUp = state.evaluate(for: accountB, missingKeys: [AccountKeys.genderIdentity])

        #expect(
            followUp?.count == 1,
            "Account B must not have its follow-up suppressed by Account A's completed check."
        )
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountB.accountId)
    }

    @Test
    func switchingBackToVerifiedAccountWithoutMissingKeys() {
        let accountA = AccountDetails.mock(id: UUID())
        let accountB = AccountDetails.mock(id: UUID())

        var state = AccountStartupCheckState(
            verifiedAccount: true,
            verifiedAccountId: accountB.accountId,
            legacyVerifiedAccount: nil
        )

        // Account A logs in with no missing keys
        let followUp = state.evaluate(for: accountA, missingKeys: [])

        #expect(followUp == nil)
        #expect(state.verifiedAccount == true)
        #expect(state.verifiedAccountId == accountA.accountId)
    }

    @Test
    func startupTimeoutWithoutAccountClearsLegacyAndMarksInitialWindowClosed() {
        var state = AccountStartupCheckState(
            verifiedAccount: false,
            verifiedAccountId: nil,
            legacyVerifiedAccount: true
        )

        state.handleStartupTimeout()

        #expect(state.verifiedAccount == true)
        #expect(state.legacyVerifiedAccount == nil)
        #expect(state.verifiedAccountId == nil)

        // A user subsequently logs in with missing keys:
        let accountC = AccountDetails.mock(id: UUID())
        let followUp = state.evaluate(for: accountC, missingKeys: [AccountKeys.name])

        #expect(followUp?.count == 1, "Late login must still be verified rather than suppressed by timeout.")
        #expect(state.verifiedAccountId == accountC.accountId)
    }
}
