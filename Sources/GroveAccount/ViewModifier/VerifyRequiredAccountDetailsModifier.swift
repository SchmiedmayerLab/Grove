//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveLegacyIdentifiers
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct FollowUpSession: Identifiable {
    var id: String {
        details.userId
    }

    let details: AccountDetails
    let requiredKeys: [any AccountKey.Type]
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct VerifyRequiredAccountDetailsModifier: ViewModifier {
    private struct DetailsState: Equatable {
        // periphery:ignore - read by the synthesized Equatable that drives change detection
        let accountId: String?
        // periphery:ignore - read by the synthesized Equatable that drives change detection
        let signedIn: Bool
        // periphery:ignore - read by the synthesized Equatable that drives change detection
        let isIncomplete: Bool? // swiftlint:disable:this discouraged_optional_boolean
        // periphery:ignore - read by the synthesized Equatable that drives change detection
        let isAnonymous: Bool?
    }
    private let enabled: Bool

    @Environment(Account.self)
    private var account

    @SceneStorage("org.grovealliance.account.startupAccountCheck")
    private var verifiedAccount = false
    @SceneStorage("org.grovealliance.account.startupAccountCheck.accountId")
    private var verifiedAccountId: String?
    @SceneStorage(LegacySceneStorageKey.accountStartupCheck)
    private var legacyVerifiedAccount: Bool?

    @State private var followUpSession: FollowUpSession?

    @MainActor private var state: DetailsState {
        DetailsState(
            accountId: account.details?.accountId,
            signedIn: account.signedIn,
            isIncomplete: account.details?.isIncomplete,
            isAnonymous: account.details?.isAnonymous
        )
    }

    nonisolated init(enabled: Bool = true) {
        self.enabled = enabled
    }


    func body(content: Content) -> some View {
        content
            .sheet(item: $followUpSession) { session in
                NavigationStack {
                    FollowUpInfoSheet(keys: session.requiredKeys)
                }
            }
            .onChange(of: state, initial: true) {
                guard enabled else {
                    return
                }

                guard let details = account.details, !details.isIncomplete, !details.isAnonymous else {
                    followUpSession = nil
                    return
                }

                var checkState = AccountStartupCheckState(
                    verifiedAccount: verifiedAccount,
                    verifiedAccountId: verifiedAccountId,
                    legacyVerifiedAccount: legacyVerifiedAccount
                )

                let missingKeys = account.configuration.missingRequiredKeys(for: details)
                if let followUpKeys = checkState.evaluate(for: details, missingKeys: missingKeys) {
                    followUpSession = FollowUpSession(details: details, requiredKeys: followUpKeys)
                }

                syncState(from: checkState)
            }
            .task {
                var checkState = AccountStartupCheckState(
                    verifiedAccount: verifiedAccount,
                    verifiedAccountId: verifiedAccountId,
                    legacyVerifiedAccount: legacyVerifiedAccount
                )

                guard !checkState.verifiedAccount else {
                    if checkState.legacyVerifiedAccount != nil {
                        checkState.legacyVerifiedAccount = nil
                        syncState(from: checkState)
                    }
                    return
                }

                try? await Task.sleep(for: .seconds(5)) // we let the initial account setup take up to 5s
                checkState.handleStartupTimeout()
                syncState(from: checkState)
            }
    }

    @MainActor
    private func syncState(from checkState: AccountStartupCheckState) {
        if verifiedAccount != checkState.verifiedAccount {
            verifiedAccount = checkState.verifiedAccount
        }
        if verifiedAccountId != checkState.verifiedAccountId {
            verifiedAccountId = checkState.verifiedAccountId
        }
        if legacyVerifiedAccount != checkState.legacyVerifiedAccount {
            legacyVerifiedAccount = checkState.legacyVerifiedAccount
        }
    }
}
