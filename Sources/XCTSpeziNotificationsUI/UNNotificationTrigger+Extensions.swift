//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziNotifications
import SwiftUI
import UserNotifications


@available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
extension UNNotificationTrigger {
    var type: LocalizedStringResource {
        if self is UNCalendarNotificationTrigger {
            LocalizedStringResource("Calendar", bundle: .atURL(from: .module))
        } else if self is UNTimeIntervalNotificationTrigger {
            LocalizedStringResource("Interval", bundle: .atURL(from: .module))
        } else if self is UNPushNotificationTrigger {
            LocalizedStringResource("Push", bundle: .atURL(from: .module))
        } else {
#if !os(visionOS) && !os(macOS) && !os(tvOS)
            if self is UNLocationNotificationTrigger {
                LocalizedStringResource("Location", bundle: .atURL(from: .module))
            } else {
                LocalizedStringResource("Unknown", bundle: .atURL(from: .module))
            }
#else
            LocalizedStringResource("Unknown", bundle: .atURL(from: .module))
#endif
        }
    }
}


@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
extension UNNotificationRequest {
    /// The next date at which the notification request will trigger, if available.
    public func nextTriggerDate() -> Date? {
        if let trigger = trigger as? UNCalendarNotificationTrigger {
            // in the case of a calendar trigger, we can safely use `nextTriggerDate()
            trigger.nextTriggerDate()
        } else if let trigger = trigger as? UNTimeIntervalNotificationTrigger {
            // in the case of a time interval trigger, we cannot use `nextTriggerDate()`,
            // since it won't actually return the next trigger date but simply add the trigger's
            // time interval to the current date.
            // this happens because the trigger itself exists completely independent of the
            // notification request it belongs to. additionally, since there's no way to obtain
            // the time a notification request was scheduled, we need to keep track of this manually.
            if let scheduledDate = content.scheduledDate {
                scheduledDate.addingTimeInterval(trigger.timeInterval)
            } else {
                nil
            }
        } else if trigger == nil {
            // if there is no trigger, the notification gets delivered immediately; in this case the trigger date would equal the schedule date
            content.scheduledDate
        } else {
            // otherwise, we cannot obtain a trigger date.
            nil
        }
    }
}
