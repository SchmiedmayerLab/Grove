//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
public import SwiftUI
public import UserNotifications


/// Present the details of a notification request.
@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct NotificationRequestView: View {
    private let request: UNNotificationRequest

    @ManagedViewUpdate private var viewUpdate

    public var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(request.identifier)
                } label: {
                    Text("Identifier", bundle: .module)
                }
                .accessibilityElement(children: .combine)
            }

#if !os(tvOS)
            content
#endif

            delivery

            trigger
        }
#if !os(tvOS)
            .navigationTitle(request.content.title)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
#endif
    }

    @available(tvOS, unavailable)
    @ViewBuilder private var content: some View {
        Section { // swiftlint:disable:this closure_body_length
            LabeledContent {
                Text(request.content.title)
            } label: {
                Text("Title", bundle: .module)
            }
                .accessibilityElement(children: .combine)

            if !request.content.subtitle.isEmpty {
                LabeledContent {
                    Text(request.content.subtitle)
                } label: {
                    Text("Subtitle", bundle: .module)
                }
                    .accessibilityElement(children: .combine)
            }

            LabeledContent {
                Text(request.content.body)
            } label: {
                Text("Body", bundle: .module)
            }
                .accessibilityElement(children: .combine)

            if !request.content.categoryIdentifier.isEmpty {
                LabeledContent {
                    Text(request.content.categoryIdentifier)
                } label: {
                    Text("Category", bundle: .module)
                }
                    .accessibilityElement(children: .combine)
            }

            if !request.content.threadIdentifier.isEmpty {
                LabeledContent {
                    Text(request.content.threadIdentifier)
                } label: {
                    Text("Thread", bundle: .module)
                }
                    .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Content", bundle: .module)
        }
    }

    @ViewBuilder private var delivery: some View {
        Section {
#if !os(tvOS)
            LabeledContent {
                Text(request.content.sound != nil ? "Yes" : "No", bundle: .module)
            } label: {
                Text("Sound", bundle: .module)
            }
                .accessibilityElement(children: .combine)
#endif

            LabeledContent {
                Text(request.content.interruptionLevel.description)
            } label: {
                Text("Interruption", bundle: .module)
            }
                .accessibilityElement(children: .combine)
        } header: {
            Text("Delivery", bundle: .module)
        }
    }

    @ViewBuilder private var trigger: some View {
        if let trigger = request.trigger {
            Section {
                LabeledContent {
                    Text(trigger.type)
                } label: {
                    Text("Type", bundle: .module)
                }
                    .accessibilityElement(children: .combine)
                if let trigger = trigger as? UNCalendarNotificationTrigger {
                    LabeledContent("Date", value: trigger.dateComponents.description)
                }
                if let nextDate = request.nextTriggerDate() {
                    LabeledContent("Next Trigger") {
                        NotificationTriggerLabel(nextDate)
                    }
                        .accessibilityElement(children: .combine)
                        .onAppear {
                            viewUpdate.schedule(at: nextDate)
                        }
                }
                LabeledContent("Repeats", value: "\(trigger.repeats)")
            } header: {
                Text("Trigger", bundle: .module)
            }
        }
    }

    /// Create a new notification request details view.
    /// - Parameter request: The notification request.
    public init(_ request: UNNotificationRequest) {
        self.request = request
    }
}
