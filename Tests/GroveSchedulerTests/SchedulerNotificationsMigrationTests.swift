//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers
@testable import GroveNotifications
@testable import GroveScheduler
import Testing
import UserNotifications


/// Notification identifiers cannot be rewritten in place — requests already registered with the
/// system are immutable — so the scheduler has to keep recognising the old ones or it loses track:
/// the old notifications keep firing while freshly scheduled duplicates pile up beside them.
@Suite
struct SchedulerNotificationsMigrationTests {
    @Test
    func recognisesTheCurrentPrefix() {
        let identifier = "\(SchedulerNotifications.baseNotificationId).task.abc"
        #expect(SchedulerNotifications.isSchedulerNotification(identifier))
    }

    @Test
    func recognisesRequestsScheduledBeforeTheRename() {
        let identifier = "\(LegacyNotifications.schedulerPrefix).task.abc"
        #expect(SchedulerNotifications.isSchedulerNotification(identifier))
    }

    @Test
    func ignoresNotificationsThatAreNotOurs() {
        #expect(!SchedulerNotifications.isSchedulerNotification("com.example.app.reminder"))
        #expect(!SchedulerNotifications.isSchedulerNotification(""))
    }

    /// The identifier carries the app's own bundle id, so a future rename of this framework cannot
    /// invalidate anything a consumer persisted.
    @Test
    func identifiersCarryNoFrameworkName() {
        let identifier = SchedulerNotifications.baseNotificationId
        #expect(!identifier.lowercased().contains("spezi"))
        #expect(!identifier.lowercased().contains("grove"))
        #expect(SchedulerNotifications.notificationTaskIdKey.hasPrefix(identifier))
    }

    /// An app that lists no scheduler identifier at all has simply not opted into background refresh
    /// -- the state of every unit-test host. Treating that as a failed migration used to trap in DEBUG
    /// and took the whole test process down with it.
    @Test
    func anAppThatPermitsNothingResolvesWithoutTrapping() {
        let resolved = PermittedBackgroundTaskIdentifier.resolved

        #expect(resolved == PermittedBackgroundTaskIdentifier.schedulerNotificationsRefresh)
        #expect(resolved.rawValue.hasSuffix(".scheduler.refresh"))
        #expect(resolved.rawValue != LegacyNotifications.schedulerBackgroundTask)
    }

    /// The identifier is the app's own bundle id plus a suffix, so renaming this framework can never
    /// invalidate a consumer's Info.plist.
    @Test
    func theIdentifierIsDerivedFromTheHostBundle() {
        let identifier = PermittedBackgroundTaskIdentifier.schedulerNotificationsRefresh.rawValue

        #expect(identifier.hasPrefix(Bundle.main.bundleIdentifier ?? "app"))
        #expect(!identifier.lowercased().contains("spezi"))
        #expect(!identifier.lowercased().contains("grove"))
    }

    @Test
    func readsAScheduledDateWrittenUnderEitherKey() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(Notifications.scheduledDate(
            fromUserInfo: [Notifications.notificationContentUserInfoKeyScheduledDate: date]
        ) == date)
        #expect(Notifications.scheduledDate(
            fromUserInfo: [LegacyNotifications.scheduledDateUserInfoKey: date]
        ) == date)
        #expect(Notifications.scheduledDate(fromUserInfo: [:]) == nil)
    }

    /// When both are present the current key wins, so a re-scheduled notification is not read back
    /// with a stale date.
    @Test
    func theCurrentScheduledDateKeyWins() {
        let current = Date(timeIntervalSince1970: 2_000_000_000)
        let legacy = Date(timeIntervalSince1970: 1_000_000_000)

        let resolved = Notifications.scheduledDate(fromUserInfo: [
            Notifications.notificationContentUserInfoKeyScheduledDate: current,
            LegacyNotifications.scheduledDateUserInfoKey: legacy
        ])

        #expect(resolved == current)
    }

    /// The authorization flag is the one whose loss is silent and lasting: a user who denied
    /// notifications before the update and grants them afterwards is only rescheduled because this
    /// value survives the rename.
    @Test
    func migratesBothPreferencesFromTheirLegacyKeys() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(date, forKey: LegacyPreferenceKey.schedulerEarliestRefreshDate)
        defaults.set(true, forKey: LegacyPreferenceKey.schedulerAuthorizationDisallowed)

        SchedulerNotifications.migrateLegacyPreferences(defaults: defaults)

        #expect(defaults.object(forKey: SchedulerNotifications.earliestScheduleRefreshDateStorageKey) as? Date == date)
        #expect(defaults.bool(forKey: SchedulerNotifications.authorizationDisallowedLastSchedulingStorageKey))
        #expect(defaults.object(forKey: LegacyPreferenceKey.schedulerEarliestRefreshDate) == nil)
        #expect(defaults.object(forKey: LegacyPreferenceKey.schedulerAuthorizationDisallowed) == nil)
    }

    /// A value already written under the new key is newer than the legacy one and must win.
    @Test
    func aCurrentPreferenceIsNotOverwrittenByTheLegacyValue() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(false, forKey: SchedulerNotifications.authorizationDisallowedLastSchedulingStorageKey)
        defaults.set(true, forKey: LegacyPreferenceKey.schedulerAuthorizationDisallowed)

        SchedulerNotifications.migrateLegacyPreferences(defaults: defaults)

        #expect(!defaults.bool(forKey: SchedulerNotifications.authorizationDisallowedLastSchedulingStorageKey))
        #expect(defaults.object(forKey: LegacyPreferenceKey.schedulerAuthorizationDisallowed) == nil)
    }

    @Test
    func readsATaskIdWrittenUnderEitherKey() {
        #expect(SchedulerNotifications.taskId(
            fromUserInfo: [SchedulerNotifications.notificationTaskIdKey: "task-a"]
        ) == "task-a")
        #expect(SchedulerNotifications.taskId(
            fromUserInfo: ["\(LegacyNotifications.schedulerPrefix).taskId": "task-b"]
        ) == "task-b")
        #expect(SchedulerNotifications.taskId(fromUserInfo: [:]) == nil)
    }

    @Test
    func theCurrentTaskIdKeyWins() {
        let resolved = SchedulerNotifications.taskId(fromUserInfo: [
            SchedulerNotifications.notificationTaskIdKey: "current",
            "\(LegacyNotifications.schedulerPrefix).taskId": "legacy"
        ])
        #expect(resolved == "current")
    }

    /// The package-visible getter is what sorts pending requests; it has to see legacy-keyed content.
    @Test
    func thePackageScheduledDateGetterAcceptsTheLegacyKey() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let content = UNMutableNotificationContent()
        content.userInfo = [LegacyNotifications.scheduledDateUserInfoKey: date]
        #expect(content.scheduledDate == date)
    }
}
