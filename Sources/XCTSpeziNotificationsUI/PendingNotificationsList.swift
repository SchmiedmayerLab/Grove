//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziNotifications
import SpeziViews
public import SwiftUI
import UserNotifications


/// Present a list of pending notifications.
@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct PendingNotificationsList: View {
    @Environment(Notifications.self)
    private var localNotifications

    @State private var viewState: ViewState = .idle
    @State private var pendingNotifications: [UNNotificationRequest] = []

    public var body: some View {
        Group {
            if viewState == .processing {
                ProgressView()
            } else if pendingNotifications.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Notifications", bundle: .module)
                    } icon: {
                        Image(systemName: "mail")
                    }
                } description: {
                    Text("No pending notification requests.", bundle: .module)
                } actions: {
                    refreshButton
                        .labelStyle(.titleOnly)
                }
            } else {
                List {
                    ForEach(pendingNotifications, id: \.identifier) { request in
                        NotificationRequestLabel(request)
                    }
                }
                    .toolbar {
                        refreshButton
                    }
            }
        }
            .navigationTitle(Text("Pending Notifications", bundle: .module))
            .task {
                await refreshList()
            }
    }

    @ViewBuilder private var refreshButton: some View {
        AsyncButton(state: $viewState) {
            await refreshList()
        } label: {
            Label {
                Text("Refresh", bundle: .module)
            } icon: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    /// Create a new list of pending notifications
    public init() {}


    private func refreshList() async {
        viewState = .processing
        defer {
            viewState = .idle
        }
        pendingNotifications.removeAll()
        pendingNotifications = await localNotifications.pendingNotificationRequests()
    }
}
