//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveBluetooth
import GroveBluetoothServices
@_spi(TestingSupport)
import GroveDevices
import GroveDevicesUI
import SwiftUI


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Bluetooth {
                Discover(MockDevice.self, by: .accessory(manufacturer: .init(rawValue: 0x01), advertising: BloodPressureService.self))
            }
            PairedDevices()
            HealthMeasurements()
            MockDeviceLoading()
        }
    }
}


@main
struct TestApp: App {
    @ApplicationDelegateAdaptor(TestAppDelegate.self)
    private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .grove(delegate)
        }
    }
}
