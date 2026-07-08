//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziDevices
import SwiftUI

@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct DeviceNameRow: View {
    private let deviceInfo: PairedDeviceInfo

    @Environment(PairedDevices.self)
    private var pairedDevices

    var body: some View {
        NavigationLink {
            NameEditView(deviceInfo) { name in
                pairedDevices.updateName(for: deviceInfo, name: name)
            }
        } label: {
            LabeledContent {
                Text(deviceInfo.name)
            } label: {
                Text("Name", bundle: .module)
            }
            .accessibilityElement(children: .combine)
        }
    }

    init(deviceInfo: PairedDeviceInfo) {
        self.deviceInfo = deviceInfo
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    let deviceInfo = PairedDeviceInfo(id: .init(), deviceType: "MockDevice", name: "BP", model: "BP5250")
    List {
        DeviceModelRow(deviceInfo: deviceInfo)
    }
        .previewWith {
            PairedDevices()
        }
}
#endif
