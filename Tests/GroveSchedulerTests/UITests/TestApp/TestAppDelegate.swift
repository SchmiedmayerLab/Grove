//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveScheduler
import UserNotifications


actor TestAppStandard: Standard, SchedulerNotificationsConstraint {
    @MainActor
    func notificationContent(for task: borrowing Task, content: borrowing UNMutableNotificationContent) {}
}


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) {
            Scheduler()
            SchedulerNotifications()
            TestAppScheduler()
        }
    }
}
