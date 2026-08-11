//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveFHIR
import GroveHealthKit


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestingStandard()) {
            FHIRStore()
            HealthKit {
                RequestReadAccess(other: TestingStandard.recordTypes)
            }
        }
    }
}
