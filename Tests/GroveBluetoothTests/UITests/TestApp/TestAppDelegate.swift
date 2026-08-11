//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveBluetooth
@_spi(TestingSupport)
import GroveBluetoothServices
import SwiftUI


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Bluetooth {
                Discover(TestDevice.self, by: .advertisedService(TestService.self))
            }
        }
    }
}
