//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit


/// A generic Bluetooth Health device.
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
public protocol HealthDevice: GenericDevice {
    /// The HealthKit device description.
    var hkDevice: HKDevice { get }
}


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
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
