//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziSensorKit
import Testing


@Suite
struct SensorKitTests {
    @Test
    @available(iOS 18, *)
    func hmmm() {
        let module = SensorKit()
        #expect(module.authorizationStatus(for: .heartRate) == .notDetermined)
    }
}
