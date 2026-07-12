//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth
@_spi(TestingSupport)
import SpeziDevices
import SpeziDevicesUI
import SwiftUI


struct BluetoothViewsTest: View {
    @State private var device = MockDevice.createMockDevice()
    @State private var presentDeviceDetails = false

    var body: some View {
        NavigationStack {
            List {
                BluetoothUnavailableSection()

                Section {
                    NearbyDeviceRow(peripheral: device, primaryAction: tapAction) {
                        presentDeviceDetails = true
                    }
                } header: {
                    LoadingSectionHeader("Devices", loading: true)
                }
            }
                .navigationTitle("Views")
                .navigationDestination(isPresented: $presentDeviceDetails) {
                    MockDeviceDetailsView(device)
                }
        }
    }


    @MainActor
    private func tapAction() {
        Task {
            switch device.state {
            case .disconnected, .disconnecting:
                try await device.connect()
            case .connecting, .connected:
                await device.disconnect()
            }
        }
    }
}


#Preview {
    BluetoothViewsTest()
}
