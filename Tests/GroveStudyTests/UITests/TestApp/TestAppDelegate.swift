//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Grove
import GroveStudy
import SwiftUI


final class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) {
            StudyManager(
                preferredLocale: Locale(identifier: "en_US"),
                persistence: .inMemory
            )
        }
    }
}
