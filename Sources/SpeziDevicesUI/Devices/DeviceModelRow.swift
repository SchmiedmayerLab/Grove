//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziDevices
import SpeziViews
import SwiftUI

@available(iOS 18, macOS 15, watchOS 11, *)
struct DeviceModelRow: View {
    private let deviceInfo: PairedDeviceInfo

    var body: some View {
        if let model = deviceInfo.model, model != deviceInfo.name {
            ListRow {
                Text("Model", bundle: .module)
            } content: {
                Text(model)
            }
        }
    }

    init(deviceInfo: PairedDeviceInfo) {
        self.deviceInfo = deviceInfo
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    let deviceInfo = PairedDeviceInfo(id: .init(), deviceType: "MockDevice", name: "BP", model: "BP5250")
    List {
        DeviceModelRow(deviceInfo: deviceInfo)
    }
}
#endif
