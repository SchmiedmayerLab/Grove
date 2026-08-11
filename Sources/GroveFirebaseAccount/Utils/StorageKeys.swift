//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers


enum StorageKeys {
    // From the vault rather than a duplicated literal: this names existing keychain and
    // LocalStorage entries that resetLegacyStorage deletes, and a duplicate is exactly how the
    // scheduler's 1.0 key got silently renamed out from under its migration.
    static let activeAccountService = LegacyKeychain.firebaseActiveAccountService
}
