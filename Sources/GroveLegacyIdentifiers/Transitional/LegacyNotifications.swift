//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Notification and background-task identifiers used before the rename.
public enum LegacyNotifications {
    /// Prefix of every notification request the scheduler registered.
    ///
    /// Requests already sitting in the system carry it, so they are cancelled and rescheduled once.
    public static let schedulerPrefix = "edu.stanford.spezi.scheduler.notification"

    /// Background-task identifier the scheduler registered for notification refresh.
    ///
    /// Unique among these in that it lives in the *consuming app's* `Info.plist`, so it cannot be
    /// migrated by code — only detected, reported, and honoured for one release.
    public static let schedulerBackgroundTask = "edu.stanford.spezi.scheduler.notifications-scheduling"

    /// `userInfo` key carrying a notification's scheduled date.
    public static let scheduledDateUserInfoKey = "edu.stanford.SpeziNotifications.notificationScheduledDate"

    /// `LocalStorage` key under which SpeziScheduler 1.0 stored its tasks.
    ///
    /// Predates even the pre-Grove layout; the scheduler still cleans up after it.
    public static let schedulerOneDotZeroTasks = "spezi.scheduler.tasks"
}
