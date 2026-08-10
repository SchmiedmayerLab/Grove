//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTHealthKit


class XCTHealthKitTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        installHealthAppNotificationsAlertMonitor()
    }
}
