//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveNotifications
import GroveViews
import OSLog
public import SwiftUI


/// Fully integrated notifications view that shows the list of pending notifications.
@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct NotificationsView: View {
    private let logger = Logger(subsystem: "org.grovealliance.notifications", category: "NotificationsView")
    private let authorizationAction: () -> Void

    @Environment(\.notificationSettings)
    private var notificationSettings
    @Environment(\.requestNotificationAuthorization)
    private var requestNotificationAuthorization

    @State private var requestAuthorization = false
    @State private var viewState: ViewState = .idle

    public var body: some View {
        PendingNotificationsList()
            .toolbar {
                if requestAuthorization {
                    AsyncButton(state: $viewState) {
                        _ = try await requestNotificationAuthorization(options: [.alert, .sound, .badge])
                        await queryAuthorization()
                        authorizationAction()
                    } label: {
                        Label {
                            Text("Request Notification Authorization", bundle: .module)
                        } icon: {
                            Image(systemName: "alarm.waves.left.and.right.fill")
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .task {
                await queryAuthorization()
            }
    }
    
    /// Create a new notifications view.
    public init() {
        self.init {}
    }
    
    /// Create a new notification view a action that is called after requesting authorization.
    /// - Parameter authorizationAction: The action that is executed once the user confirms the notification authorization.
    public init(authorizationAction: @escaping () -> Void) {
        self.authorizationAction = authorizationAction
    }

    private func queryAuthorization() async {
        let status = await notificationSettings().authorizationStatus
        requestAuthorization = status != .authorized && status != .denied
        logger.debug("Notification authorization is now \(status.description)")
    }
}
