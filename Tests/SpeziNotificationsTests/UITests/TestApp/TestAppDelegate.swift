//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziNotifications


final class TestAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Notifications()
        }
    }
}
