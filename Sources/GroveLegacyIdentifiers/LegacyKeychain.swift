//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Keychain service and server names used before the rename.
public enum LegacyKeychain {
    /// Generic-password service holding every access guard's passcode.
    public static let accessGuardService = "edu.stanford.spezi.accessGuard"

    /// Internet-password server for the Firebase account service marker.
    ///
    /// Not a migration target. `FirebaseAccountService.resetLegacyStorage` only ever *deletes* under
    /// this name, so renaming it would leave the real item on every upgraded device forever.
    public static let firebaseActiveAccountService = "active-service.firebase.stanford.edu"

    /// Keychain service under which early releases persisted the user's email and password for
    /// re-authentication. Long dead: nothing has written or read it for years, but devices from
    /// that era still carry the stale secret. Swept (deleted, never read) on launch.
    public static let firebaseEmailPasswordCredentials = "account.email-pw.firebase.stanford.edu"
}
