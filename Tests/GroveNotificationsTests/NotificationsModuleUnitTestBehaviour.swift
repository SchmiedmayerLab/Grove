//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveNotifications
import Testing
import UserNotifications


@Suite
struct NotificationsModuleUnitTestBehaviour {
    @Test
    @MainActor
    func testNotificationsModuleIsNonFunctional() async throws {
        let module = Notifications()
        #if !os(watchOS)
        try await module.setBadgeCount(12)
        #endif
        try await module.add(request: UNNotificationRequest(identifier: "abc", content: UNMutableNotificationContent(), trigger: nil))
        #expect(try await module.remainingNotificationLimit() == 0)
        #expect(await module.pendingNotificationRequests().isEmpty)
        #if !os(tvOS)
        #expect(await module.deliveredNotifications().isEmpty)
        await module.add(categories: [UNNotificationCategory(identifier: "abc", actions: [], intentIdentifiers: [])])
        #endif
        await module.removePendingNotificationRequests(where: { _ in true })
    }
}
