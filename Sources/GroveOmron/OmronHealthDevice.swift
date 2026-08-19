//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveBluetooth
public import GroveDevices


/// An Omron Health Device.
///
/// An Omron Health Device is a `HealthDevice` that is pairable.
/// Further, it might adopt the `BatteryPoweredDevice` protocol if the Omron device supports the battery service.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol OmronHealthDevice: HealthDevice, PairableDevice {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronHealthDevice {
    /// The Omron model string.
    public var model: OmronModel {
        OmronModel(rawValue: deviceInformation.modelNumber ?? "Generic Health Device")
    }

    /// The Omron Manufacturer data observed in the Bluetooth advertisement.
    public var manufacturerData: OmronManufacturerData? {
        guard let manufacturerData = advertisementData.manufacturerData else {
            return nil
        }
        return OmronManufacturerData(data: manufacturerData)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension OmronHealthDevice {
    /// Default implementation determining if device is in pairing mode.
    ///
    /// Pairing mode is advertised by the device through the ``manufacturerData`` in the Bluetooth advertisement.
    public var isInPairingMode: Bool {
        if case .pairingMode = manufacturerData?.pairingMode {
            return true
        } else if let localName = advertisementData.localName.map({ OmronLocalName(rawValue: $0) }),
                  case .pairingMode = localName?.pairingMode {
            return true
        }
        return false
    }
}
