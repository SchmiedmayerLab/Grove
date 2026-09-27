//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// `@SceneStorage` keys written before the rename.
public enum LegacySceneStorageKey {
    /// Completion marker for the startup account requirements check.
    ///
    /// Transitional scene storage key read once on upgrade to migrate the account startup-check state.
    /// Deleted along with the migration that consumes it, no earlier than one minor release after 0.3.0.
    public static let accountStartupCheck = "edu.stanford.spezi-account.startup-account-check"
}
