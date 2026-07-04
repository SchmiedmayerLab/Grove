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


@Observable
@MainActor
class FirebaseAccountModel {
    var authorizationController: AuthorizationController?

    var isPresentingReauthentication = false
    var reauthenticationContext: ReauthenticationContext?

    var isPresentingEmailChangeNotice = false
    private(set) var pendingEmailAddress: String?

    nonisolated init() {}


    func presentEmailChangeNotice(for newEmail: String) {
        pendingEmailAddress = newEmail
        isPresentingEmailChangeNotice = true
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
