//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveBluetooth


/// A Bluetooth device that is pairable.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol PairableDevice: GenericDevice {
    /// Persistent identifier for the device type.
    ///
    /// This is used to associate pairing information with the implementing device. By default, the type name is used.
    static var deviceTypeIdentifier: String { get }

    /// Indicate that the device is nearby.
    ///
    /// Use the [`DeviceState`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceState(\.nearby) var nearby
    /// ```
    var nearby: Bool { get }

    /// Connect action.
    ///
    /// Use the [`DeviceAction`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceAction(\.connect) var connect
    /// ```
    ///
    var connect: BluetoothConnectAction { get }

    /// Disconnect action.
    ///
    /// Use the [`DeviceAction`](../../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md) property wrapper to
    /// declare this property.
    /// ```swift
    /// @DeviceAction(\.disconnect) var disconnect
    /// ```
    var disconnect: BluetoothDisconnectAction { get }

    /// Determines if the device is currently able to get paired.
    ///
    /// This might be a value that is reported by the device for example through the manufacturer data in the Bluetooth advertisement.
    var isInPairingMode: Bool { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PairableDevice {
    /// Default persistent identifier for the device type.
    ///
    /// Defaults to the Swift type name.
    public static var deviceTypeIdentifier: String {
        "\(Self.self)"
    }
}
