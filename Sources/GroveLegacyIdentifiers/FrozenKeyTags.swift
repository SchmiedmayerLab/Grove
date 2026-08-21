//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Cryptographic key tags that must never change.
///
/// Not deprecated, and not transitional in the usual sense: these tag the Secure Enclave keypair that
/// encrypts `LocalStorage`. The private key is non-exportable, so a changed tag makes every encrypted
/// file permanently unreadable with no migration possible.
public enum FrozenKeyTags {
    /// Prefix of the tag under which `LocalStorage` stores its encryption keypair.
    ///
    /// - Important: Frozen. Reads like a module name; is not one.
    public static let localStorageKeyPrefix = "LocalStorage."
}
