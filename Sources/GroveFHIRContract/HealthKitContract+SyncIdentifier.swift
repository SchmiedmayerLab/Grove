//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

extension HealthKitContract {
    /// What every readable sync identifier system under the native record identifier's `system` starts with; the writing
    /// application's bundle identifier follows (HealthKit guide `mapping.md`, readable sync identifier).
    package static func syncIdentifierSystemPrefix(in system: String) -> String {
        "\(system)/\(syncIdentifierSystemPathSegment)/"
    }

    /// Whether `bundleIdentifier` can be the final segment of a readable sync identifier's system: nonempty, and only
    /// ASCII letters, digits, hyphens and periods, the characters of an Apple bundle identifier and of the catalog's
    /// writer segment pattern.
    package static func isSyncIdentifierWriterSegment(_ bundleIdentifier: String) -> Bool {
        !bundleIdentifier.isEmpty && bundleIdentifier.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E }
    }
}
