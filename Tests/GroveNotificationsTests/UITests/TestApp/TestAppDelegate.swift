//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveNotifications


final class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Notifications()
        }
    }
}
