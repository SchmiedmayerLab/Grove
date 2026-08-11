//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UserNotifications)
import UserNotifications


@available(iOS 18, macOS 15, watchOS 11, *)
class GroveNotificationCenterDelegate: NSObject {
#if !os(tvOS)
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // This method HAS to run on the Main Actor.
        // This method is generated through Objective-C interoperability, and is originally defined with a completion handler.
        // The completion handler MUST be called from the main thread (as this method is called on the main thread).
        // However, if you do not annotate with @MainActor, an async method will be executed on the background thread.
        // The completion handler would also be called on a background thread which results in a crash.
        // Declaring the method as @MainActor requires a @preconcurrency inheritance from the delegate to silence Sendable warnings.

        await withTaskGroup(of: Void.self) { group in
            guard let delegate = GroveAppDelegate.appDelegate else {
                return
            }

            for handler in delegate.grove.notificationHandler {
                group.addTask { @Sendable @MainActor in
                    await handler.handleNotificationAction(response)
                }
            }

            await group.waitForAll()
        }
    }
#endif

    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await withTaskGroup(of: UNNotificationPresentationOptions?.self) { group in
            guard let delegate = GroveAppDelegate.appDelegate else {
                return []
            }

            for handler in delegate.grove.notificationHandler {
                group.addTask { @Sendable @MainActor in
                    await handler.receiveIncomingNotification(notification)
                }
            }

            var hasSpecified = false

            var unionOptions: UNNotificationPresentationOptions = []
            for await options in group {
                guard let options else {
                    continue
                }
                unionOptions.formUnion(options)
                hasSpecified = true
            }

            if hasSpecified {
                return unionOptions
            } else {
                return [.badge, .badge, .list, .sound]
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveNotificationCenterDelegate: @preconcurrency UNUserNotificationCenterDelegate {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveAppDelegate {
    func setupNotificationDelegate() {
        guard !grove.notificationHandler.isEmpty else {
            return
        }

        let center = UNUserNotificationCenter.current()

        let delegate = GroveNotificationCenterDelegate()
        Self.notificationDelegate = delegate // maintain reference
        center.delegate = delegate
    }
}
#endif
