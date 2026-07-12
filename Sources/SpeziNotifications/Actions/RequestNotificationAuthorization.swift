//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SwiftUI
import UserNotifications


@available(iOS 18, macOS 15, watchOS 11, *)
extension Spezi {
    /// An action to request notification authorization.
    ///
    /// Refer to ``Spezi/requestNotificationAuthorization`` for documentation.
    public struct RequestNotificationAuthorizationAction {
        fileprivate init() {}

        /// Request notification authorization.
        /// - parameter options: The authorization options your app is requesting.
        /// - returns: A Boolean value indicating whether the user granted the requested permissions.
        public func callAsFunction(options: UNAuthorizationOptions) async throws -> Bool {
            try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        }
    }

    /// Request notification authorization.
    ///
    /// ```swift
    /// struct MyModule: Module {
    ///     @Application(\.requestNotificationAuthorization)
    ///     private var requestNotificationAuthorization
    ///
    ///     func notificationPermissionWhileOnboarding() async throws -> Bool {
    ///         try await requestNotificationAuthorization(options: [.alert, .badge, .sound])
    ///     }
    /// }
    /// ```
    ///
    /// ## Topics
    /// ### Action
    /// - ``RequestNotificationAuthorizationAction``
    public var requestNotificationAuthorization: RequestNotificationAuthorizationAction {
        RequestNotificationAuthorizationAction()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// Request notification authorization.
    ///
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.requestNotificationAuthorization)
    ///     private var requestNotificationAuthorization
    ///
    ///     var body: some View {
    ///         Button("Allow Notifications") {
    ///             Task {
    ///                 try await requestNotificationAuthorization(options: [.alert, .badge, .sound])
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    public var requestNotificationAuthorization: Spezi.RequestNotificationAuthorizationAction {
        Spezi.RequestNotificationAuthorizationAction()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Spezi.RequestNotificationAuthorizationAction: Sendable {}
