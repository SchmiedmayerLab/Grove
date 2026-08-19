//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI
import UserNotifications


@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
struct NotificationRequestLabel: View {
    private let request: UNNotificationRequest

    @ManagedViewUpdate private var viewUpdate

    var body: some View {
        NavigationLink {
            NotificationRequestView(request)
        } label: {
            VStack(alignment: .leading) {
#if os(tvOS)
                Text("Notification", bundle: .module)
#else
                Text(request.content.title)
                    .bold()
#endif
                if let nextDate = request.nextTriggerDate() {
                    NotificationTriggerLabel(nextDate)
                        .foregroundStyle(.secondary)
                        .onAppear {
                            viewUpdate.schedule(at: nextDate)
                        }
                }
            }
        }
    }

    init(_ request: UNNotificationRequest) {
        self.request = request
    }
}
