//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import Observation
import SwiftUI


/// An email address change that was requested but is still pending verification through the confirmation link.
struct PendingEmailChange: Equatable, Sendable {
    /// The Firebase user identifier (`uid`) of the account the change was requested for.
    let accountId: String
    /// The new email address that is pending verification.
    let emailAddress: String
}


@Observable
@MainActor
class FirebaseAccountModel {
    var authorizationController: AuthorizationController?

    var isPresentingReauthentication = false
    var reauthenticationContext: ReauthenticationContext?

    var isPresentingEmailChangeNotice = false
    private(set) var pendingEmailChange: PendingEmailChange?

    nonisolated init() {}


    func presentEmailChangeNotice(_ change: PendingEmailChange) {
        pendingEmailChange = change
        isPresentingEmailChangeNotice = true
    }

    func clearPendingEmailChange(for accountId: String) {
        guard pendingEmailChange?.accountId == accountId else {
            return
        }
        pendingEmailChange = nil
    }

    func reauthenticateUser(userId: String) async -> ReauthenticationResult {
        defer {
            reauthenticationContext = nil
            isPresentingReauthentication = false
        }

        return await withCheckedContinuation { continuation in
            isPresentingReauthentication = true
            reauthenticationContext = ReauthenticationContext(userId: userId, continuation: continuation)
        }
    }
}


extension FirebaseAccountModel: Sendable {}
