//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import TipKit


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct ForgetDeviceTip: Tip {
    static let instance = ForgetDeviceTip()

    @Parameter static var hasRemovedPairedDevice: Bool = false

    var title: Text {
        Text("Fully Unpair Device", bundle: .module)
    }

    var message: Text? {
        Text("Make sure to to remove the device from the Bluetooth settings to fully unpair the device.", bundle: .module)
    }

    var actions: [Action] {
        Action {
            guard let url = URL(string: "App-Prefs:root=General") else {
                return
            }
            Task { @MainActor in
#if canImport(UIKit)
                UIApplication.shared.open(url)
#elseif os(macOS)
                NSWorkspace.shared.open(url)
#endif
            }
        } _: {
            Text("Open Settings", bundle: .module)
        }
    }

    var image: Image? {
        Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.hierarchical)
    }

    var rules: [Rule] {
        #Rule(Self.$hasRemovedPairedDevice) {
            $0 == true
        }
    }
}
