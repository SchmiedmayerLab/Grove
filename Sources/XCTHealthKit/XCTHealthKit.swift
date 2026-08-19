//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OSLog
import XCTest

let logger = Logger(subsystem: "org.grovealliance.xctHealthKit", category: "")


extension XCTest {
    static let isIOS26OrGreater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
}
