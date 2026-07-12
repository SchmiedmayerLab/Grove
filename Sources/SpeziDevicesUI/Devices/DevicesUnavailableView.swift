//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct DevicesUnavailableView: View {
    private let pairNewDevice: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Text("No Devices", bundle: .module)
                .fontWeight(.semibold)
        } description: {
            Text("Paired devices will appear here once set up.", bundle: .module)
        } actions: {
            if let pairNewDevice {
                Button(action: pairNewDevice) {
                    Text("Pair New Device", bundle: .module)
                }
            }
        }
    }


    init(showPairing pairNewDevice: (() -> Void)?) {
        self.pairNewDevice = pairNewDevice
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    DevicesUnavailableView {}
}
#endif
