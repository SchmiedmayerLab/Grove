//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import GroveDevices
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct PairedDeviceView: View {
    private let device: any PairableDevice
    private let appName: String

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        PaneContent(
            title: .init("Accessory Paired", bundle: .module),
            subtitle: .init("\"\(device.label)\" was successfully paired with the \(appName) app.", bundle: .module)
        ) {
            AccessoryImageView(device)
        } action: {
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
                    .frame(maxWidth: .infinity, maxHeight: 35)
            }
            .buttonStyle(.borderedProminent)
            .padding([.leading, .trailing], 36)
        }
    }


    init(_ device: any PairableDevice, appName: String) {
        self.device = device
        self.appName = appName
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    SheetPreview {
        PairedDeviceView(MockDevice.createMockDevice(), appName: "Example")
    }
}
#endif
