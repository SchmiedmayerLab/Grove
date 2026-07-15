//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth
@_spi(TestingSupport)
public import SpeziDevices
import SpeziViews
public import SwiftUI


/// A row that displays information of a nearby Bluetooth peripheral in a List view.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct NearbyDeviceRow<Label: View>: View {
    private let peripheral: any GenericBluetoothPeripheral
    private let label: Label
    private let devicePrimaryActionClosure: () -> Void
    private let secondaryActionClosure: (() -> Void)?

    public var body: some View {
        HStack {
            Button(action: devicePrimaryAction) {
                HStack {
                    label

                    Spacer()

                    if peripheral.state == .connecting || peripheral.state == .disconnecting {
                        ProgressView()
                            .accessibilityRemoveTraits(.updatesFrequently)
                            .foregroundStyle(.secondary)
                    }
                }
            }
                .accessibilityAddTraits(.isButton)
                .tint(.primary)

            if secondaryActionClosure != nil && peripheral.state == .connected {
                InfoButton(Text("Device Details", bundle: .module), action: deviceDetailsAction)
            }
        }
            .accessibilityElement(children: .combine)
    }


    /// Create a new nearby device row.
    /// - Parameters:
    ///   - peripheral: The nearby peripheral.
    ///   - primaryAction: The action that is executed when tapping the peripheral.
    ///     It is recommended to connect or disconnect devices when tapping on them.
    ///   - secondaryAction: The action that is executed when the device details button is pressed.
    ///     The device details button is displayed once the peripheral is connected.
    public init(
        peripheral: any GenericBluetoothPeripheral,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) where Label == LabeledContent<PeripheralLabel, PeripheralSecondaryLabel> {
        self.init(peripheral: peripheral, primaryAction: primaryAction, secondaryAction: secondaryAction) {
            LabeledContent {
                PeripheralSecondaryLabel(peripheral)
            } label: {
                PeripheralLabel(peripheral)
            }
        }
    }
    
    /// Creates a new nearby device row.
    /// - Parameters:
    ///   - peripheral: The nearby peripheral.
    ///   - primaryAction: The action that is executed when tapping the peripheral.
    ///     It is recommended to connect or disconnect devices when tapping on them.
    ///   - secondaryAction: The action that is executed when the device details button is pressed.
    ///     The device details button is displayed once the peripheral is connected.
    ///   - label: The label that is displayed for the row.
    public init(
        peripheral: any GenericBluetoothPeripheral,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.peripheral = peripheral
        self.label = label()
        self.devicePrimaryActionClosure = primaryAction
        self.secondaryActionClosure = secondaryAction
    }


    private func devicePrimaryAction() {
        devicePrimaryActionClosure()
    }

    private func deviceDetailsAction() {
        if let secondaryActionClosure {
            secondaryActionClosure()
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview { // swiftlint:disable:this closure_body_length
    List {
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "MyDevice 1", state: .connecting)) {
            print("Clicked")
        } secondaryAction: {
        }
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "MyDevice 2", state: .connected)) {
            print("Clicked")
        } secondaryAction: {
            print("Secondary Clicked!")
        }
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "Long MyDevice 3", state: .connected, requiresUserAttention: true)) {
            print("Clicked")
        } secondaryAction: {
            print("Secondary Clicked!")
        }
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "MyDevice 4", state: .disconnecting)) {
            print("Clicked")
        } secondaryAction: {
        }
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "MyDevice 5", state: .disconnected)) {
            print("Clicked")
        } secondaryAction: {
        }

        let peripheral = MockBluetoothPeripheral(label: "MyDevice 2", state: .connected)
        NearbyDeviceRow(peripheral: MockBluetoothPeripheral(label: "MyDevice 2", state: .connected)) {
            print("Clicked")
        } secondaryAction: {
            print("Secondary Clicked!")
        } label: {
            ListRow {
                PeripheralLabel(peripheral)
                Text("RSSI: -64")
            } content: {
                PeripheralSecondaryLabel(peripheral)
            }
        }
    }
}
#endif
