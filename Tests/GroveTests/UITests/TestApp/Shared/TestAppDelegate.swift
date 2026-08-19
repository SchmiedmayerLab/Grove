//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import SwiftUI


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            if FeatureFlags.lifecycleTests {
                LifecycleHandlerTestModule()
            }
            ModuleWithModifier()
            ModuleWithModel()
            NotificationModule()
            ModuleWithService()
        }
    }
}
