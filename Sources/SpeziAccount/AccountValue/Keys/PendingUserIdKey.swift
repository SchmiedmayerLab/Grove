//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation


extension AccountDetails {
    private struct PendingUserIdKey: KnowledgeSource {
        typealias Anchor = AccountAnchor
        typealias Value = String
    }

    /// A new user identifier that was requested but is still pending confirmation.
    ///
    /// An account service can set this property to indicate that a change of the ``userId`` was requested but did not take effect yet
    /// (e.g., the user still needs to open a verification link that was sent to their new email address).
    /// Views like `AccountOverview` display this information alongside the current user identifier.
    ///
    /// - Note: This is transient, in-memory state supplied by the account service with the rest of the account details.
    ///     It is generally not persisted and, therefore, might not be available across application launches.
    public var pendingUserId: String? {
        get {
            self[PendingUserIdKey.self]
        }
        set {
            self[PendingUserIdKey.self] = newValue
        }
    }
}
