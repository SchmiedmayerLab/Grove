//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziBluetooth
import SpeziBluetoothServices


/// A battery powered Bluetooth device.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public protocol BatteryPoweredDevice: BluetoothDevice {
    /// The battery service of the peripheral.
    ///
    /// Use the [`@Service`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @Service var deviceInformation = BatteryService()
    /// ```
    var battery: BatteryService { get }
}
