//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// `UserDefaults` keys written before the rename.
public enum LegacyPreferenceKey {
    /// Earliest date the scheduler should refresh its notifications.
    public static let schedulerEarliestRefreshDate = "edu.stanford.spezi.scheduler.earliestScheduleRefreshDate"

    /// Whether the last scheduling attempt was blocked by notification authorization.
    public static let schedulerAuthorizationDisallowed = "edu.stanford.spezi.scheduler.authorizationDisallowedLastScheduling"

    /// Whether any device has ever been paired.
    public static let devicesEverPairedOnce = "edu.stanford.spezi.SpeziDevices.ever-paired-once"

    /// Whether the one-shot AccessorySetupKit migration has run. Losing this re-prompts the user to pair.
    public static let devicesAccessorySetupKitMigration = "edu.stanford.spezi.SpeziDevices.askit-migration"
}
