//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ByteCoding
import CoreBluetooth
@_spi(APISupport)
import Spezi
@_spi(TestingSupport)
import SpeziBluetooth
import SpeziBluetoothServices
@_spi(TestingSupport)
import SpeziDevices
import SpeziDevicesUI
@_spi(TestingSupport)
import SpeziOmron
import SpeziViews
import SwiftUI


class MockDeviceLoading: Module, EnvironmentAccessible {
    @Application(\.spezi)
    private var spezi

    init() {}

    @MainActor
    func loadMockDevice(_ device: some PairableDevice) {
        spezi.loadModule(device, ownership: .external)
    }
}


struct DevicesTestView: View {
    @Environment(PairedDevices.self)
    private var pairedDevices
    @Environment(MockDeviceLoading.self)
    private var moduleLoading

    @State private var didRegister = false
    @State private var device = MockDevice.createMockDevice()
    @State private var weightScale = OmronWeightScale.createMockDevice(manufacturerData: .omronManufacturerData(mode: .transferMode))
    @State private var bloodPressureCuffBP5250 = OmronBloodPressureCuff.createMockDevice(
        manufacturerData: .omronManufacturerData(mode: .transferMode)
    )
    @State private var bloodPressureCuffBP7000 = OmronBloodPressureCuff.createMockDevice(
        name: "BLEsmart_0000011F",
        manufacturerData: .omronManufacturerData(mode: .transferMode)
    )

    @State private var viewState: ViewState = .idle

    @ToolbarContentBuilder @MainActor private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryAction) {
            Button("Discover Device", systemImage: "plus.rectangle.fill.on.rectangle.fill") {
                device.isInPairingMode = true
                device.$advertisementData.inject(AdvertisementData()) // trigger onChange advertisement
            }
            AsyncButton(state: $viewState) {
                try await device.connect()
                try await weightScale.connect()
                try await bloodPressureCuffBP5250.connect()
                try await bloodPressureCuffBP7000.connect()
            } label: {
                Label("Connect", systemImage: "cable.connector")
            }
            AsyncButton {
                await device.disconnect()
                await weightScale.disconnect()
                await bloodPressureCuffBP5250.disconnect()
                await bloodPressureCuffBP7000.disconnect()
            } label: {
                Label("Disconnect", systemImage: "cable.connector.slash")
            }

            omronDevicesMenu
        }
    }

    @MainActor private var omronDevicesMenu: some View {
        Menu("Omron Devices", systemImage: "heart.text.square") {
            Button("Discover Weight Scale", systemImage: "scalemass.fill") {
                weightScale.$advertisementData.inject(AdvertisementData(
                    manufacturerData: OmronManufacturerData.omronManufacturerData(mode: .pairingMode).encode()
                ))
            }
            Menu("Discover Blood Pressure Cuff", systemImage: "heart.fill") {
                Button("BP 5250") {
                    bloodPressureCuffBP5250.$advertisementData.inject(AdvertisementData(
                        manufacturerData: OmronManufacturerData.omronManufacturerData(mode: .pairingMode).encode()
                    ))
                }

                Button("BP 7000") {
                    bloodPressureCuffBP7000.$advertisementData.inject(AdvertisementData(
                        manufacturerData: OmronManufacturerData.omronManufacturerData(mode: .pairingMode).encode()
                    ))
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            DevicesView(appName: "Example", pairingHint: "Enable pairing mode on the device.")
                .toolbar {
                    toolbarContent
                }
        }
            .viewStateAlert(state: $viewState)
            .onAppear {
                guard !didRegister else {
                    return
                }

                moduleLoading.loadMockDevice(device)
                moduleLoading.loadMockDevice(weightScale)
                moduleLoading.loadMockDevice(bloodPressureCuffBP5250)
                moduleLoading.loadMockDevice(bloodPressureCuffBP7000)

                // simulator this being called in the configure method of the device
                pairedDevices.configure(device: device, accessing: device.$state, device.$advertisementData, device.$nearby)
                pairedDevices.configure(device: weightScale, accessing: weightScale.$state, weightScale.$advertisementData, weightScale.$nearby)
                pairedDevices.configure(
                    device: bloodPressureCuffBP5250,
                    accessing: bloodPressureCuffBP5250.$state,
                    bloodPressureCuffBP5250.$advertisementData,
                    bloodPressureCuffBP5250.$nearby
                )
                pairedDevices.configure(
                    device: bloodPressureCuffBP7000,
                    accessing: bloodPressureCuffBP7000.$state,
                    bloodPressureCuffBP7000.$advertisementData,
                    bloodPressureCuffBP7000.$nearby
                )
                didRegister = true
            }
    }
}


extension OmronManufacturerData {
    static func omronManufacturerData(mode: OmronManufacturerData.PairingMode) -> OmronManufacturerData {
        OmronManufacturerData(pairingMode: mode, users: [
            .init(id: 1, sequenceNumber: 2, recordsNumber: 1)
        ])
    }
}


#Preview {
    DevicesTestView()
        .previewWith {
            PairedDevices()
            MockDeviceLoading()
            Bluetooth {
                Discover(MockDevice.self, by: .accessory(manufacturer: .init(rawValue: 0x01), advertising: BloodPressureService.self))
            }
        }
}
