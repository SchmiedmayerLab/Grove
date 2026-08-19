//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import HealthKit


/// A generic Bluetooth Health device.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol HealthDevice: GenericDevice {
    /// The HealthKit device description.
    var hkDevice: HKDevice { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthDevice {
    /// The HealthKit device description.
    ///
    /// Default implementation using the `DeviceInformationService`.
    public var hkDevice: HKDevice {
        HKDevice(
            name: name,
            manufacturer: deviceInformation.manufacturerName,
            model: deviceInformation.modelNumber,
            hardwareVersion: deviceInformation.hardwareRevision,
            firmwareVersion: deviceInformation.firmwareRevision,
            softwareVersion: deviceInformation.softwareRevision,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }
}
