//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveBluetooth
import GroveDevices
import GroveDevicesUI
import SwiftUI


struct ContentView: View {
    var body: some View {
        TabView {
            DevicesTestView()
                .tabItem {
                    Label("Devices", systemImage: "sensor.fill")
                }
            MeasurementsTestView()
                .tabItem {
                    Label("Measurements", systemImage: "list.bullet.clipboard.fill")
                }
            BluetoothViewsTest()
                .tabItem {
                    Label("Views", systemImage: "macwindow")
                }
        }
    }
}


#Preview {
    ContentView()
        .previewWith {
            MockDeviceLoading()
            PairedDevices()
            HealthMeasurements()
            Bluetooth {}
        }
}
