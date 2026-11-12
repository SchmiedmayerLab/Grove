//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove


#if compiler(>=6.4)
@diagnose(DeprecatedDeclaration, as: ignored, reason: "Covers Grove's deprecated remote notification actions.")
#endif
@MainActor
class NotificationModule: Module, EnvironmentAccessible {
    @Application(\.registerRemoteNotifications)
    var registerRemoteNotifications

    @Application(\.unregisterRemoteNotifications)
    var unregisterRemoteNotifications
}
