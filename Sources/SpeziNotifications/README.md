<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziNotifications


Simplify User Notifications in Spezi-based applications.

## Overview

[`SpeziNotifications`](SpeziNotifications.docc/SpeziNotifications.md) simplifies interaction with user notifications by adding additional actions to the Environment of SwiftUI Views and
Spezi [`Module`](../Spezi/Spezi.docc/Module/Module.md)s.

### Schedule Notifications

You can use the [`Notifications`](SpeziNotifications.docc/SpeziNotifications.md)
module to interact with user notifications within your application. You can either define it as a dependency
of your Spezi [`Module`](../Spezi/Spezi.docc/Module/Module.md)
or retrieve it from the environment using the [`@Environment`](https://developer.apple.com/documentation/swiftui/environment)
property wrapper in your SwiftUI View.

The code example below schedules a notification request, accessing the `Notifications` module from within the custom `MyNotifications` module.

```swift
import Spezi
import UserNotifications


final class MyNotifications: Module {
    @Dependency(Notifications.self)
    private var notifications

    @Application(\.notificationSettings)
    private var settings

    func scheduleAppointmentReminder() async throws {
        let status = await settings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            return // no authorization to schedule notification
        }

        let content = UNMutableNotificationContent()
        content.title = "Your Appointment"
        content.body = "Your appointment is in 3 hours"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 60, repeats: false)

        let request = UNNotificationRequest(identifier: "3-hour-reminder", content: content, trigger: trigger)

        try await notifications.add(request: request)
    }
}
```

### Requesting Authorization in SwiftUI

The Notification module and notification-related actions are also available in the SwiftUI Environment. The code example below creates a simple
notification authorization onboarding view that (1) determines the current authorization status and (2) request notification authorization
when the user taps the button.


```swift
import SpeziNotifications
import SpeziViews

struct NotificationOnboarding: View {
    @Environment(\.notificationSettings)
    private var notificationSettings
    @Environment(\.requestNotificationAuthorization)
    private var requestNotificationAuthorization

    @State private var viewState: ViewState = .idle
    @State private var notificationsAuthorized = false

    var body: some View {
        VStack {
            // ...
            if notificationsAuthorized {
                Button("Continue") {
                    // show next view ...
                }
            } else {
                AsyncButton("Allow Notifications", state: $viewState) {
                    try await requestNotificationAuthorization(options: [.alert, .badge, .sound])
                }
                    .environment(\.defaultErrorDescription, "Failed to request notification authorization.")
            }
        }
            .viewStateAlert(state: $viewState)
            .task {
                notificationsAuthorized = await notificationSettings().authorizationStatus == .authorized
            }
    }
}
```

> [!IMPORTANT]
> The example above uses `AsyncButton`
> and the `ViewState` model from [SpeziViews](../SpeziViews/SpeziViews.docc/SpeziViews.md) to more
> easily manage the state of asynchronous actions and handle erroneous conditions.

## Setup

Add the Spezi monorepo package to your app and select the `SpeziNotifications` product.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SpeziNotifications", package: "Spezi")
    ]
)
```

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.
