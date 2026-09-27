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
    /// The documentation shows one screen at a time; a tab bar for the test app's other screens is chrome that
    /// an app embedding these views would not have. The launch says which screen that is.
    private var documentationScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--documentation") else {
            return nil
        }
        guard let index = arguments.firstIndex(of: "--screen"), arguments.indices.contains(index + 1) else {
            return "devices"
        }
        return arguments[index + 1]
    }

    var body: some View {
        switch documentationScreen {
        case "devices": DevicesTestView()
        case "measurements": MeasurementsTestView()
        case .some: BluetoothViewsTest()
        case nil: tabs
        }
    }

    @ViewBuilder private var tabs: some View {
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
