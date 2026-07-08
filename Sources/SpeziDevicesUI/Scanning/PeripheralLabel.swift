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
import SwiftUI


/// The label of a bluetooth peripheral.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public struct PeripheralLabel: View {
    private let peripheral: any GenericBluetoothPeripheral

    public var body: some View {
        Text(peripheral.label)
            .accessibilityLabel(Text(peripheral.accessibilityLabel))
    }
    
    /// Create a new bluetooth peripheral label.
    /// - Parameter peripheral: The peripheral to describe.
    public init(_ peripheral: any GenericBluetoothPeripheral) {
        self.peripheral = peripheral
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    List {
        PeripheralLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .connected))
    }
}
#endif
