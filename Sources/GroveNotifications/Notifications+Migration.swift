//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import GroveLegacyIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension Notifications {
    /// Reads a notification's scheduled date, accepting the key used before the rename.
    ///
    /// Notifications already registered with the system carry the old key and keep being delivered
    /// after the update, so both spellings have to resolve for as long as one of those can still fire.
    public static func scheduledDate(fromUserInfo userInfo: [AnyHashable: Any]) -> Date? {
        if let date = userInfo[notificationContentUserInfoKeyScheduledDate] as? Date {
            return date
        }
        return userInfo[LegacyNotifications.scheduledDateUserInfoKey] as? Date
    }
}
