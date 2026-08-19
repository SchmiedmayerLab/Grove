//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
@_spi(APISupport)
import Grove
import GroveFoundation
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove {
    /// Registers to receive remote notifications through Apple Push Notification service.
    ///
    /// Refer to the documentation of ``Grove/registerRemoteNotifications``.
    public struct RegisterForRemoteNotificationsAction {
        private weak var grove: Grove?

        fileprivate init(_ grove: Grove) {
            self.grove = grove
        }

        /// Registers to receive remote notifications through Apple Push Notification service.
        ///
        /// - Returns: A globally unique token that identifies this device to APNs.
        ///     Send this token to the server that you use to generate remote notifications.
        ///     Your server must pass this token unmodified back to APNs when sending those remote notifications.
        ///     For more information refer to the documentation of
        ///     [`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622958-application).
        /// - Throws: Registration might fail if the user's device isn't connected to the network or
        ///     if your app is not properly configured for remote notifications. It might also throw a `TimeoutError` when running on a simulator device running on a host
        ///     that is not connected to an Apple ID.
        @discardableResult
        @MainActor
        public func callAsFunction() async throws -> Data {
            guard let grove else {
                preconditionFailure("RegisterRemoteNotificationsAction was used in a scope where Grove was not available anymore!")
            }

            return try await grove.remoteNotificationRegistrationSupport()
        }
    }

    /// Registers to receive remote notifications through Apple Push Notification service.
    ///
    /// For more information refer to the [`registerForRemoteNotifications()`](https://developer.apple.com/documentation/uikit/uiapplication/1623078-registerforremotenotifications)
    /// documentation for `UIApplication` or for the respective equivalent for your current platform.
    ///
    /// - Note: For more information on the general topic on how to register your app with APNs,
    ///     refer to the [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
    ///     article.
    ///
    /// Below is a short code example on how to use this action within your [`Module`](../../Grove/Grove.docc/Module/Module.md).
    ///
    /// - Warning: Registering for Remote Notifications on Simulator devices might not be possible if your are not signed into an Apple ID on the host machine.
    ///     The method might throw a [`TimeoutError`](../../GroveFoundation/GroveFoundation.docc/GroveFoundation.md)
    ///     in such a case.
    ///
    /// ```swift
    /// import GroveFoundation
    ///
    /// class ExampleModule: Module {
    ///     @Application(\.registerRemoteNotifications)
    ///     var registerRemoteNotifications
    ///
    ///     func handleNotificationsPermissions() async throws {
    ///         // Make sure to request notifications permissions before registering for remote notifications ...
    ///
    ///
    ///         do {
    ///             let deviceToken = try await registerRemoteNotifications()
    ///         } catch let error as TimeoutError {
    /// #if targetEnvironment(simulator)
    ///             return // override logic when running within a simulator
    /// #else
    ///             throw error
    /// #endif
    ///         }
    ///
    ///         // .. send the device token to your remote server that generates push notifications
    ///     }
    /// }
    /// ```
    ///
    /// > Tip: Make sure to request authorization by calling ``requestNotificationAuthorization``
    ///     to have your remote notifications be able to display alerts, badges or use sound. Otherwise, all remote notifications will be delivered silently.
    ///
    /// ## Topics
    /// ### Action
    /// - ``RegisterForRemoteNotificationsAction``
    public var registerRemoteNotifications: RegisterForRemoteNotificationsAction {
        RegisterForRemoteNotificationsAction(self)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// Registers to receive remote notifications through Apple Push Notification service.
    ///
    /// For more information refer to the [`registerForRemoteNotifications()`](https://developer.apple.com/documentation/uikit/uiapplication/1623078-registerforremotenotifications)
    /// documentation for `UIApplication` or for the respective equivalent for your current platform.
    ///
    /// - Note: For more information on the general topic on how to register your app with APNs,
    ///     refer to the [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
    ///     article.
    ///
    /// Below is a short code example on how to use this action within your [`Module`](../../Grove/Grove.docc/Module/Module.md).
    ///
    /// - Warning: Registering for Remote Notifications on Simulator devices might not be possible if your are not signed into an Apple ID on the host machine.
    ///     The method might throw a [`TimeoutError`](../../GroveFoundation/GroveFoundation.docc/GroveFoundation.md)
    ///     in such a case.
    ///
    /// ```swift
    /// import GroveFoundation
    ///
    /// struct ExampleView: View {
    ///     @Environment(\.registerRemoteNotifications)
    ///     private var registerRemoteNotifications
    ///
    ///     var body: some View {
    ///         // ...
    ///     }
    ///
    ///     private func handleNotificationsPermissions() async throws {
    ///         // Make sure to request notifications permissions before registering for remote notifications
    ///         try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    ///
    ///
    ///         do {
    ///             let deviceToken = try await registerRemoteNotifications()
    ///         } catch let error as TimeoutError {
    /// #if targetEnvironment(simulator)
    ///             return // override logic when running within a simulator
    /// #else
    ///             throw error
    /// #endif
    ///         }
    ///
    ///         // .. send the device token to your remote server that generates push notifications
    ///     }
    /// }
    /// ```
    ///
    /// > Tip: Make sure to request authorization by calling ``requestNotificationAuthorization``
    ///     to have your remote notifications be able to display alerts, badges or use sound. Otherwise, all remote notifications will be delivered silently.
    @MainActor public var registerRemoteNotifications: Grove.RegisterForRemoteNotificationsAction {
        guard let grove = GroveAppDelegate.grove else {
            preconditionFailure("@Environment(\\.registerRemoteNotifications) can only be accessed within a Grove application.")
        }
        return Grove.RegisterForRemoteNotificationsAction(grove)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove.RegisterForRemoteNotificationsAction: Sendable {}
