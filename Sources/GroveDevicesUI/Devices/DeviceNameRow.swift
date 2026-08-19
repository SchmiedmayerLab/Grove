//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveDevices
import SwiftUI

@available(iOS 18, macOS 15, watchOS 11, *)
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
@available(iOS 18, macOS 15, watchOS 11, *)
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
