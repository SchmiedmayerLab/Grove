//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Foundation
import GroveLegacyIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension SchedulerNotifications {
    /// Whether a notification request was scheduled by this module, under any identifier it has used.
    ///
    /// Requests registered with the system before the update still carry the pre-Grove prefix, and
    /// they have to keep being recognised or the scheduler loses track of them: the old ones keep
    /// firing while freshly scheduled duplicates pile up beside them.
    ///
    /// The current prefix is checked first, so the common case does no extra work and the legacy
    /// branch is only reached by a request that really is old.
    ///
    /// Use this rather than comparing prefixes yourself — a hand-written check against the current
    /// prefix silently stops recognising notifications scheduled before the update.
    ///
    /// ```swift
    /// func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) {
    ///     guard SchedulerNotifications.isSchedulerNotification(response.notification.request.identifier) else {
    ///         return  // not ours
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter identifier: A `UNNotificationRequest` identifier.
    /// - Returns: Whether the scheduler scheduled it, under the current or the pre-Grove prefix.
    nonisolated public static func isSchedulerNotification(_ identifier: String) -> Bool {
        if identifier.hasPrefix(baseNotificationId) {
            return true
        }
        guard identifier.hasPrefix(LegacyNotifications.schedulerPrefix) else {
            return false
        }
        LegacyIdentifierReport.encountered(
            LegacyNotifications.schedulerPrefix,
            in: "GroveScheduler"
        )
        return true
    }

    /// Reads the scheduler task id from a notification's `userInfo`, accepting the key used before
    /// the rename.
    ///
    /// Notifications scheduled before the update remain pending with the old key and keep being
    /// delivered after it, so both spellings have to resolve for as long as one of those can fire.
    /// Use this rather than subscripting `userInfo` with ``notificationTaskIdKey`` directly.
    ///
    /// - Parameter userInfo: The notification content's `userInfo` dictionary.
    /// - Returns: The task id, or `nil` if the notification was not scheduled by the scheduler.
    nonisolated public static func taskId(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        if let id = userInfo[notificationTaskIdKey] as? String {
            return id
        }
        return userInfo["\(LegacyNotifications.schedulerPrefix).taskId"] as? String
    }
}
#endif
