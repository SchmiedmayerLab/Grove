//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import SpeziDevices
import SwiftUI


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
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
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    SheetPreview {
        PairedDeviceView(MockDevice.createMockDevice(), appName: "Example")
    }
}
#endif
