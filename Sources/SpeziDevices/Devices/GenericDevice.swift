//
// This source file is part of the Stanford Spezi open-project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziBluetooth
import SpeziBluetoothServices


/// A generic Bluetooth device.
///
/// A generic Bluetooth device that provides access to basic device information.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public protocol GenericDevice: BluetoothDevice, GenericBluetoothPeripheral, Identifiable, Sendable {
    /// The device identifier.
    ///
    /// Use the [`DeviceState`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceState(\.id) var id
    /// ```
    var id: UUID { get }

    /// The device name.
    ///
    /// Use the [`DeviceState`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceState(\.name) var name
    /// ```
    var name: String? { get }

    /// The advertisement data received in the latest advertisement.
    ///
    /// Use the [`DeviceState`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceState(\.advertisementData) var advertisementData
    /// ```
    var advertisementData: AdvertisementData { get }

    /// The device information service of the peripheral.
    ///
    /// Use the [`@Service`](../../SpeziBluetooth/SpeziBluetooth.docc/SpeziBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @Service var deviceInformation = DeviceInformationService()
    /// ```
    var deviceInformation: DeviceInformationService { get }
}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
extension GenericDevice {
    /// Default label implementation.
    ///
    /// Returns `"Generic Device"` if the peripheral doesn't expose a ``name``.
    public var label: String {
        name ?? "Generic Device"
    }
}
