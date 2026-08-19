//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Grove
import GroveScheduler
import GroveStudy
import SwiftUI


final class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) {
            // StudyManager depends on the Scheduler; without configuring it here it would be
            // default-initialised on disk, outliving the in-memory enrollments across launches.
            Scheduler(persistence: .inMemory)
            StudyManager(
                preferredLocale: Locale(identifier: "en_US"),
                persistence: .inMemory
            )
        }
    }
}
