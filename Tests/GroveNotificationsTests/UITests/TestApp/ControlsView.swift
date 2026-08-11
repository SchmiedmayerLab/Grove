//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveNotifications
import GroveViews
import SwiftUI
import UserNotifications


struct ControlsView: View {
    @Environment(\.notificationSettings)
    private var notificationSettings
    @Environment(\.requestNotificationAuthorization)
    private var requestNotificationAuthorization

    @Environment(\.registerRemoteNotifications)
    private var registerRemoteNotifications
    @Environment(\.unregisterRemoteNotifications)
    private var unregisterRemoteNotifications

    @Environment(Notifications.self)
    private var notifications

    @State private var token: Data?
    @State private var tokenError: Error?
    @State private var authorizationStatus: UNAuthorizationStatus?
    @State private var viewState: ViewState = .idle

    @State private var task: Task<Void, Never>? {
        willSet {
            task?.cancel()
        }
    }


    var body: some View {
        List { // swiftlint:disable:this closure_body_length
            Section {
                if let authorizationStatus {
                    LabeledContent("Authorization", value: authorizationStatus.description)
                }
                LabeledContent("Token") {
                    if let token {
                        Text(token.description)
                            .foregroundStyle(.green)
                    } else if let error = tokenError as? LocalizedError,
                              let description = error.errorDescription ?? error.failureReason {
                        Text(verbatim: description)
                            .foregroundStyle(.red)
                    } else if tokenError != nil {
                        Text(verbatim: "failed")
                            .foregroundStyle(.red)
                    } else {
                        Text(verbatim: "none")
                            .foregroundStyle(.secondary)
                    }
                }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("token-field")
            }

            Section("Actions") {
                Button("Register") {
                    task = Task {
                        do {
                            token = try await registerRemoteNotifications()
                        } catch {
                            print("Registration failed with \(error)")
                            self.tokenError = error
                        }
                    }
                }
                Button("Unregister") {
                    unregisterRemoteNotifications()
                    token = nil
                    tokenError = nil
                }
                if authorizationStatus != .authorized {
                    AsyncButton("Request Authorization", state: $viewState) {
                        do {
                            try await requestNotificationAuthorization(options: [.alert, .badge, .sound])
                            authorizationStatus = await notificationSettings().authorizationStatus
                        } catch {
                            authorizationStatus = await notificationSettings().authorizationStatus
                            throw error
                        }
                    }
                }
                if authorizationStatus != .denied {
                    AsyncButton("Schedule Notifications", state: $viewState) {
                        try await scheduleNotifications()
                    }
                    AsyncButton("Cancel Pending Notifications") {
                        await notifications.removePendingNotificationRequests { _ in true }
                    }
                }
            }
        }
            .navigationTitle("Notifications")
            .viewStateAlert(state: $viewState)
            .task {
                authorizationStatus = await notificationSettings().authorizationStatus
            }
            .onDisappear {
                task?.cancel()
            }
    }

    private func scheduleNotifications() async throws {
        let settings = await notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            try await requestNotificationAuthorization(options: [.alert, .badge, .sound, .provisional])
            authorizationStatus = await notificationSettings().authorizationStatus
        }

        try await notifications.add(request: .calendarRequest)
        try await notifications.add(request: .intervalRequest)
    }
}


extension UNNotificationContent {
    static func content(type: String, interruption: UNNotificationInterruptionLevel = .active) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
#if !os(tvOS)
        content.title = "\(type) Notification"
        content.subtitle = "Test Notification"
        content.body = "This is a \(type.lowercased()) notification"

        content.categoryIdentifier = "\(type.lowercased())-test-notification"
        content.threadIdentifier = "GroveNotifications"
        content.interruptionLevel = interruption
        content.sound = .default
#endif

        return content
    }
}


extension UNNotificationTrigger {
    static var calendarTrigger: UNNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 8, minute: 0, second: 0), repeats: true)
    }

    static var intervalTrigger: UNNotificationTrigger {
        UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
    }
}


extension UNNotificationRequest {
    static var calendarRequest: UNNotificationRequest {
        UNNotificationRequest(
            identifier: "calendar-request",
            content: .content(type: "Calendar", interruption: .timeSensitive),
            trigger: .calendarTrigger
        )
    }

    static var intervalRequest: UNNotificationRequest {
        UNNotificationRequest(identifier: "interval-request", content: .content(type: "Interval", interruption: .critical), trigger: .intervalTrigger)
    }
}
