//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveBluetooth
public import GroveBluetoothServices


/// A battery powered Bluetooth device.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol BatteryPoweredDevice: BluetoothDevice {
    /// The battery service of the peripheral.
    ///
    /// Use the [`@Service`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @Service var deviceInformation = BatteryService()
    /// ```
    var battery: BatteryService { get }
}
