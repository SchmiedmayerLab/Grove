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


/// A secondary label of a Bluetooth peripheral.
///
/// The secondary label describes the state of the Bluetooth peripheral (e.g., `connecting` or `connected`).
/// It might be empty in a `disconnected` state.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public struct PeripheralSecondaryLabel: View {
    private let peripheral: any GenericBluetoothPeripheral

    private var localizationSecondaryLabel: LocalizedStringResource? {
        if peripheral.requiresUserAttention {
            return .init("Intervention Required", bundle: .atURL(from: .module))
        }
        switch peripheral.state {
        case .connecting:
            return .init("Connecting", bundle: .atURL(from: .module))
        case .connected:
            return .init("Connected", bundle: .atURL(from: .module))
        case .disconnecting:
            return .init("Disconnecting", bundle: .atURL(from: .module))
        case .disconnected:
            return nil
        }
    }

    public var body: some View {
        Group {
            if peripheral.requiresUserAttention {
                Text("Requires Attention", bundle: .module)
            } else {
                switch peripheral.state {
                case .connecting, .disconnecting:
                    EmptyView()
                case .connected:
                    Text("Connected", bundle: .module)
                case .disconnected:
                    EmptyView()
                }
            }
        }
            .accessibilityRepresentation {
                if let localizationSecondaryLabel {
                    Text(localizationSecondaryLabel)
                }
            }
    }
    
    /// Create a new secondary peripheral label.
    /// - Parameter peripheral: The Bluetooth peripheral.
    public init(_ peripheral: any GenericBluetoothPeripheral) {
        self.peripheral = peripheral
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    List {
        PeripheralSecondaryLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .connecting))
        PeripheralSecondaryLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .connected))
        PeripheralSecondaryLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .connected, requiresUserAttention: true))
        PeripheralSecondaryLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .disconnecting))
        PeripheralSecondaryLabel(MockBluetoothPeripheral(label: "MyDevice 1", state: .disconnected))
    }
}
#endif
