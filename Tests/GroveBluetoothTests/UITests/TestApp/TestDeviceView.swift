//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ByteCoding
@_spi(TestingSupport)
import GroveBluetooth
@_spi(TestingSupport)
import GroveBluetoothServices
import SwiftUI


struct TestDeviceView: View {
    private let device: TestDevice

    var body: some View {
        List {
            DeviceInformationView(device)

            TestServiceView(device.testService)
        }
            .navigationTitle("Interactions")
            .navigationBarTitleDisplayMode(.inline)
    }

    init(device: TestDevice) {
        self.device = device
    }
}


#if DEBUG
#Preview {
    let device = TestDevice()
    device.deviceInformation.$manufacturerName.inject("Apple Inc.")
    device.deviceInformation.$modelNumber.inject("MacBookPro18,1")

    let service = device.testService
    service.$eventLog.inject(.receivedWrite(.readWriteStringCharacteristic, value: "Hello Grove".encode()))

    service.$readString.inject("Hello World (1)")
    service.$readWriteString.inject("Hello World")

    return NavigationStack {
        TestDeviceView(device: device)
    }
}
#endif
