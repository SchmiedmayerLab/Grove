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


@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
extension Spezi {
    /// An action to request the current user notifications settings.
    ///
    /// Refer to ``Spezi/notificationSettings`` for documentation.
    public struct NotificationSettingsAction {
        fileprivate init() {}

        /// Request the current user notification settings.
        /// - Returns: Returns the current user notification settings.
        public func callAsFunction() async -> sending UNNotificationSettings {
            await UNUserNotificationCenter.current().notificationSettings()
        }
    }
    
    /// Retrieve the current notification settings of the application.
    ///
    /// ```swift
    /// struct MyModule: Module {
    ///     @Application(\.notificationSettings)
    ///     private var notificationSettings
    ///
    ///     func deliverNotification(request: UNNotificationRequest) async throws {
    ///         let settings = await notificationSettings()
    ///         guard settings.authorizationStatus == .authorized
    ///                 || settings.authorizationStatus == .provisional else {
    ///             return // notifications not permitted
    ///         }
    ///
    ///         // continue to add the notification request to the center ...
    ///     }
    /// }
    /// ```
    ///
    /// ## Topics
    /// ### Action
    /// - ``NotificationSettingsAction``
    public var notificationSettings: NotificationSettingsAction {
        NotificationSettingsAction()
    }
}


@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
extension EnvironmentValues {
    /// Retrieve the current notification settings of the application.
    ///
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.notificationSettings)
    ///     private var notificationSettings
    ///
    ///     @State private var requestAuthorization = false
    ///
    ///     var body: some View {
    ///         List {
    ///             if requestAuthorization {
    ///                 Button("Allow Notifications") {
    ///                     Task {
    ///                         try await requestNotificationAuthorization(options: [.alert, .badge, .sound])
    ///                     }
    ///                 }
    ///             }
    ///         }
    ///             .task {
    ///                 requestAuthorization = try? await notificationSettings() != .authorized
    ///             }
    ///     }
    /// }
    /// ```
    public var notificationSettings: Spezi.NotificationSettingsAction {
        Spezi.NotificationSettingsAction()
    }
}


@available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
extension Spezi.NotificationSettingsAction: Sendable {}
